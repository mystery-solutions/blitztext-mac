import AppKit

// MARK: - Hotkey Binding

/// Ein frei belegbarer Trigger für genau einen `WorkflowType`.
///
/// Zwei Registrierungspfade werden unterstützt (siehe `HotkeyService`):
/// - `usesFnModifier == true`: klassischer fn-Kombi-Pfad über den NSEvent
///   `.flagsChanged`-Monitor (nur auf Apple-internen Tastaturen zuverlässig,
///   da Fremdtastaturen wie die KB066 kein systemweites `.function`-Event senden).
/// - `usesFnModifier == false`: tastatur-unabhängige Standard-Modifier-Kombi
///   (⌘/⌃/⌥/⇧ + Taste) über Carbon `RegisterEventHotKey`, mit NSEvent-Monitor
///   als Fallback.
///
/// `modifiers` enthält ausschließlich die "echten" Modifier (⇧⌃⌥⌘); der
/// fn-Modifier wird separat über `usesFnModifier` abgebildet.
struct HotkeyBinding: Codable, Equatable, Hashable {
    /// Serialisierbarer Roh-Wert von `NSEvent.ModifierFlags` (nur relevante Modifier).
    var modifiersRawValue: UInt
    /// Virtueller Keycode der Basistaste (0 = keine, nur für fn-Kombis sinnvoll).
    var keyCode: UInt16
    /// fn-Modifier verwenden (klassischer .function-Pfad).
    var usesFnModifier: Bool

    /// Nur diese Modifier werden ausgewertet/gespeichert (kein capsLock/numericPad/help).
    static let relevantModifiers: NSEvent.ModifierFlags = [.shift, .control, .option, .command]

    var modifiers: NSEvent.ModifierFlags {
        get { NSEvent.ModifierFlags(rawValue: modifiersRawValue).intersection(Self.relevantModifiers) }
        set { modifiersRawValue = newValue.intersection(Self.relevantModifiers).rawValue }
    }

    init(modifiers: NSEvent.ModifierFlags, keyCode: UInt16, usesFnModifier: Bool) {
        self.modifiersRawValue = modifiers.intersection(Self.relevantModifiers).rawValue
        self.keyCode = keyCode
        self.usesFnModifier = usesFnModifier
    }

    // MARK: - Matching

    /// Flags-Set, das der fn-Pfad exakt erwarten muss (Modifier ∪ .function).
    var expectedFnFlags: NSEvent.ModifierFlags {
        modifiers.union(.function)
    }

    /// Prüft, ob ein (bereinigtes) Modifier-Set + Keycode diese Standard-Kombi trifft.
    func matchesStandard(flags: NSEvent.ModifierFlags, keyCode: UInt16) -> Bool {
        guard !usesFnModifier else { return false }
        return flags.intersection(Self.relevantModifiers) == modifiers && keyCode == self.keyCode
    }

    /// Ist die Kombi grundsätzlich gültig (registrierbar)?
    /// - Standard-Kombis brauchen eine Basistaste.
    /// - fn-Kombis brauchen mindestens fn (immer erfüllt) — Modifier optional.
    var isValid: Bool {
        if usesFnModifier { return true }
        return keyCode != 0
    }

    // MARK: - Conflict

    /// Zwei Bindings, die denselben Schlüssel liefern, feuern auf dieselbe Kombi.
    var conflictKey: String {
        if usesFnModifier {
            return "fn:\(modifiers.rawValue)"
        }
        return "std:\(keyCode):\(modifiers.rawValue)"
    }

    func conflicts(with other: HotkeyBinding) -> Bool {
        conflictKey == other.conflictKey
    }

    // MARK: - Display

    /// Menschlich lesbare Kurzform, z. B. "fn ⇧" oder "⌘⇧A".
    var displayString: String {
        var parts: [String] = []
        if usesFnModifier { parts.append("fn") }
        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }
        if keyCode != 0, let key = Self.keyName(for: keyCode) {
            parts.append(key)
        }
        if parts.isEmpty { return "—" }
        return parts.joined(separator: " ")
    }

    // MARK: - Defaults

    /// Aktuelle Zuordnung 1:1 aus dem bisherigen `HotkeyService` (alle fn-basiert).
    static func defaultBinding(for type: WorkflowType) -> HotkeyBinding {
        switch type {
        case .transcription:
            return HotkeyBinding(modifiers: [.shift], keyCode: 0, usesFnModifier: true)
        case .localTranscription:
            return HotkeyBinding(modifiers: [.shift, .control], keyCode: 0, usesFnModifier: true)
        case .textImprover:
            return HotkeyBinding(modifiers: [.control], keyCode: 0, usesFnModifier: true)
        case .dampfAblassen:
            return HotkeyBinding(modifiers: [.option], keyCode: 0, usesFnModifier: true)
        case .emojiText:
            return HotkeyBinding(modifiers: [.command], keyCode: 0, usesFnModifier: true)
        }
    }

    /// Vollständiges Default-Set, getypt.
    static var defaults: [WorkflowType: HotkeyBinding] {
        Dictionary(uniqueKeysWithValues: WorkflowType.allCases.map { ($0, defaultBinding(for: $0)) })
    }

    /// Default-Set, keyed by rawValue — direkt für die Persistenz.
    static var defaultsByRawValue: [String: HotkeyBinding] {
        Dictionary(uniqueKeysWithValues: WorkflowType.allCases.map { ($0.rawValue, defaultBinding(for: $0)) })
    }

    // MARK: - Keycode Names (US-Layout Virtual Keycodes)

    private static let keyNames: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7",
        27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P",
        36: "↩", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
        45: "N", 46: "M", 47: ".", 48: "⇥", 49: "Space", 50: "`", 51: "⌫", 53: "esc",
        65: ".", 67: "*", 69: "+", 71: "Clear", 75: "/", 76: "↩", 78: "-", 81: "=",
        82: "0", 83: "1", 84: "2", 85: "3", 86: "4", 87: "5", 88: "6", 89: "7", 91: "8", 92: "9",
        96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9", 103: "F11",
        105: "F13", 107: "F14", 109: "F10", 111: "F12", 113: "F15",
        114: "Help", 115: "Home", 116: "PageUp", 117: "⌦", 118: "F4", 119: "End",
        120: "F2", 121: "PageDown", 122: "F1", 123: "←", 124: "→", 125: "↓", 126: "↑"
    ]

    static func keyName(for keyCode: UInt16) -> String? {
        keyNames[keyCode] ?? "Key \(keyCode)"
    }
}
