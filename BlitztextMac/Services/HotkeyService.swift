import Cocoa
import Observation

enum HotkeyMode: String, Codable, CaseIterable, Identifiable {
    case hold    // Tasten halten = aufnehmen, loslassen = stoppen
    case toggle  // Einmal drücken = starten, nochmal/Escape = stoppen

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hold: return "Halten"
        case .toggle: return "Drücken"
        }
    }

    var description: String {
        switch self {
        case .hold: return "Tasten halten zum Aufnehmen, loslassen zum Stoppen"
        case .toggle: return "Einmal drücken zum Starten, nochmal oder Escape zum Stoppen"
        }
    }
}

enum HotkeyEvent {
    case down(WorkflowType)  // Keys pressed
    case up(WorkflowType)    // Keys released (for hold mode)
    case cancel              // Escape pressed
}

/// Registrierungs-/Matching-Layer für die frei belegbaren Trigger.
///
/// Zwei Pfade, gesteuert durch `HotkeyBinding.usesFnModifier`:
/// - **fn-Kombis** (`usesFnModifier == true`, modifier-only): klassischer
///   `.flagsChanged`-Monitor. Nur auf Apple-internen Tastaturen zuverlässig, da
///   Fremdtastaturen (KB066) kein systemweites `.function`-Event senden.
/// - **Standard-Kombis** (`usesFnModifier == false`, ⌘/⌃/⌥/⇧ + Taste):
///   systemweit & tastatur-unabhängig über Carbon `RegisterEventHotKey`
///   (`CarbonHotKeyCenter`). Scheitert die Registrierung, weicht der Workflow auf
///   einen generischen `NSEvent`-`keyDown`/`keyUp`-Monitor aus, der
///   `modifierFlags` + `keyCode` ebenso tastatur-unabhängig matcht.
///
/// `updateBindings(_:)` deregistriert sauber alles und registriert neu — für
/// Live-Änderungen aus dem Settings-UI ohne App-Neustart.
@Observable
@MainActor
final class HotkeyService {
    private var flagsGlobalMonitor: Any?
    private var flagsLocalMonitor: Any?
    private var keyDownMonitor: Any?
    private var keyUpMonitor: Any?
    private var activeCombo: WorkflowType?  // Which combo is currently held

    /// Aktuelle Bindings, getypt. Start: fn-Defaults, bis `updateBindings` läuft.
    private var bindings: [WorkflowType: HotkeyBinding] = HotkeyBinding.defaults
    /// Standard-Kombis, deren Carbon-Registrierung scheiterte → NSEvent-Fallback.
    private var monitorFallbackWorkflows: Set<WorkflowType> = []

    var onHotkeyEvent: ((HotkeyEvent) -> Void)?

    /// Workflows, die aktuell auf den NSEvent-Monitor-Fallback angewiesen sind
    /// (Carbon-Registrierung fehlgeschlagen) — für UI-Statusanzeige.
    var fallbackWorkflows: Set<WorkflowType> { monitorFallbackWorkflows }

    func start() {
        installFlagsMonitors()
        installKeyMonitors()
        CarbonHotKeyCenter.shared.onEvent = { [weak self] workflow, isDown in
            self?.handleCarbonEvent(workflow: workflow, isDown: isDown)
        }
        applyBindings()
    }

    func stop() {
        removeMonitors()
        CarbonHotKeyCenter.shared.onEvent = nil
        CarbonHotKeyCenter.shared.unregisterAll()
        activeCombo = nil
    }

    /// Bindings austauschen und alle Registrierungen erneuern (kein Neustart nötig).
    func updateBindings(_ newBindings: [WorkflowType: HotkeyBinding]) {
        bindings = newBindings
        activeCombo = nil
        applyBindings()
    }

    // MARK: - Registration

    private func applyBindings() {
        // Alte Standard-Registrierungen sauber abräumen (Requirement 6).
        CarbonHotKeyCenter.shared.unregisterAll()
        monitorFallbackWorkflows.removeAll()

        for (workflow, binding) in bindings {
            guard binding.isValid, !binding.usesFnModifier else { continue }
            let registered = CarbonHotKeyCenter.shared.register(
                workflow: workflow,
                keyCode: binding.keyCode,
                modifiers: binding.modifiers
            )
            if !registered {
                // Carbon-Kombi belegt/nicht abbildbar → generischer Monitor-Fallback.
                monitorFallbackWorkflows.insert(workflow)
            }
        }
        // fn-Kombis brauchen keine Registrierung; sie werden im flagsChanged-Pfad
        // dynamisch gegen `bindings` gematcht.
    }

    // MARK: - Monitors

    private func installFlagsMonitors() {
        guard flagsGlobalMonitor == nil else { return }
        flagsGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in self?.handleFlags(event) }
        }
        flagsLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in self?.handleFlags(event) }
            return event
        }
    }

    private func installKeyMonitors() {
        guard keyDownMonitor == nil else { return }
        keyDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in self?.handleKeyDown(event) }
        }
        keyUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyUp) { [weak self] event in
            Task { @MainActor in self?.handleKeyUp(event) }
        }
    }

    private func removeMonitors() {
        for monitor in [flagsGlobalMonitor, flagsLocalMonitor, keyDownMonitor, keyUpMonitor] {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
        flagsGlobalMonitor = nil
        flagsLocalMonitor = nil
        keyDownMonitor = nil
        keyUpMonitor = nil
    }

    // MARK: - fn path (.flagsChanged)

    private func handleFlags(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Passt das aktuelle Modifier-Set exakt auf eine fn-Kombi?
        if let match = fnBinding(matching: flags) {
            if activeCombo == nil {
                activeCombo = match
                onHotkeyEvent?(.down(match))
            }
            return
        }

        // Modifier losgelassen → nur für eine aktive fn-Kombi ein up feuern.
        // (Standard-Kombis lösen ihr up über Carbon/keyUp aus.)
        if let combo = activeCombo, bindings[combo]?.usesFnModifier == true {
            activeCombo = nil
            onHotkeyEvent?(.up(combo))
        }
    }

    private func fnBinding(matching flags: NSEvent.ModifierFlags) -> WorkflowType? {
        for (workflow, binding) in bindings where binding.usesFnModifier && binding.isValid {
            if flags == binding.expectedFnFlags { return workflow }
        }
        return nil
    }

    // MARK: - Standard path (Carbon)

    private func handleCarbonEvent(workflow: WorkflowType, isDown: Bool) {
        if isDown {
            if activeCombo == nil {
                activeCombo = workflow
                onHotkeyEvent?(.down(workflow))
            }
        } else if activeCombo == workflow {
            activeCombo = nil
            onHotkeyEvent?(.up(workflow))
        }
    }

    // MARK: - Standard path (NSEvent fallback) + Escape

    private func handleKeyDown(_ event: NSEvent) {
        // Escape → cancel (toggle mode), wenn keine relevanten Modifier gehalten.
        if event.keyCode == 53,
           event.modifierFlags.intersection(HotkeyBinding.relevantModifiers).isEmpty {
            handleEscape()
            return
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // Nur Fallback-Workflows matchen hier — Carbon-registrierte feuern über Carbon.
        for workflow in monitorFallbackWorkflows {
            guard let binding = bindings[workflow] else { continue }
            if binding.matchesStandard(flags: flags, keyCode: event.keyCode) {
                if activeCombo == nil {
                    activeCombo = workflow
                    onHotkeyEvent?(.down(workflow))
                }
                return
            }
        }
    }

    private func handleKeyUp(_ event: NSEvent) {
        // Backstop für alle aktiven Standard-Kombis: löst das up beim Loslassen der
        // Basistaste aus — deckt auch unzuverlässige Carbon-Released-Events ab.
        guard let combo = activeCombo,
              let binding = bindings[combo],
              !binding.usesFnModifier,
              binding.keyCode == event.keyCode else { return }
        activeCombo = nil
        onHotkeyEvent?(.up(combo))
    }

    private func handleEscape() {
        activeCombo = nil
        onHotkeyEvent?(.cancel)
    }
}
