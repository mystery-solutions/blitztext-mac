import AppKit
import Carbon.HIToolbox

// MARK: - Carbon Hotkey Center

/// Dünner Wrapper um Carbon `RegisterEventHotKey`, damit Standard-Modifier-Kombis
/// (⌘/⌃/⌥/⇧ + Taste) **systemweit und tastatur-unabhängig** zünden — anders als der
/// fn-Pfad, den Fremdtastaturen wie die KB066 nicht systemweit senden.
///
/// Alle Zugriffe laufen auf dem Main-Thread: `register`/`unregisterAll` werden vom
/// `@MainActor`-`HotkeyService` aufgerufen, der C-Callback hüpft per
/// `DispatchQueue.main.async` + `MainActor.assumeIsolated` zurück auf Main.
@MainActor
final class CarbonHotKeyCenter {
    static let shared = CarbonHotKeyCenter()

    /// FourCharCode-Signatur ("BLTZ") für unsere Hotkey-IDs.
    private static let signature: OSType = 0x424C_545A

    private var eventHandler: EventHandlerRef?
    private var registrations: [UInt32: (ref: EventHotKeyRef, workflow: WorkflowType)] = [:]
    private var nextID: UInt32 = 1

    /// Wird bei jedem Hotkey-Event aufgerufen: `(workflow, isDown)`. Läuft auf Main.
    var onEvent: ((WorkflowType, Bool) -> Void)?

    private init() {}

    // MARK: - Handler

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }

        var eventTypes = [
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            ),
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyReleased)
            )
        ]

        InstallEventHandler(
            GetEventDispatcherTarget(),
            blitztextCarbonHotKeyHandler,
            eventTypes.count,
            &eventTypes,
            nil,
            &eventHandler
        )
    }

    // MARK: - Registration

    /// Registriert eine Standard-Kombi. Gibt `false` zurück, wenn `RegisterEventHotKey`
    /// scheitert (z. B. Kombi bereits belegt) — der Aufrufer weicht dann auf den
    /// NSEvent-Monitor-Fallback aus.
    func register(workflow: WorkflowType, keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        installHandlerIfNeeded()

        let id = nextID
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        var ref: EventHotKeyRef?

        let status = RegisterEventHotKey(
            UInt32(keyCode),
            Self.carbonModifiers(from: modifiers),
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &ref
        )

        guard status == noErr, let ref else { return false }

        registrations[id] = (ref, workflow)
        nextID += 1
        return true
    }

    func unregisterAll() {
        for (_, registration) in registrations {
            UnregisterEventHotKey(registration.ref)
        }
        registrations.removeAll()
    }

    /// Vom C-Callback (bereits auf Main) aufgerufen.
    fileprivate func dispatch(id: UInt32, isDown: Bool) {
        guard let registration = registrations[id] else { return }
        onEvent?(registration.workflow, isDown)
    }

    // MARK: - Modifier Mapping

    private static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        return carbon
    }
}

// MARK: - C Callback

/// Globaler C-kompatibler Handler (kein Capture-Kontext), damit er als
/// `EventHandlerUPP` an Carbon übergeben werden kann.
private func blitztextCarbonHotKeyHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event else { return OSStatus(eventNotHandledErr) }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return OSStatus(eventNotHandledErr) }

    let isDown = GetEventKind(event) == UInt32(kEventHotKeyPressed)
    let id = hotKeyID.id

    DispatchQueue.main.async {
        MainActor.assumeIsolated {
            CarbonHotKeyCenter.shared.dispatch(id: id, isDown: isDown)
        }
    }

    return noErr
}
