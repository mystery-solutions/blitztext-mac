# Changelog — Blitztext (macOS)

Format orientiert an [Keep a Changelog](https://keepachangelog.com/de/).

## [Unreleased]

### Hinzugefügt
- **Konfigurierbare Hotkeys / Trigger-Picker** (SE-T-714). Jeder Workflow-Trigger
  ist im Tab *Anpassen → Tastenkürzel* frei belegbar und wird persistent in
  `AppSettings.hotkeyBindings` (`[WorkflowType.rawValue: HotkeyBinding]`, JSON)
  gespeichert; fehlt/korrupt → Fallback auf die bisherigen fn-Defaults. Neben dem
  bisherigen fn-Pfad (nur Apple-interne Tastaturen) gibt es jetzt einen
  **tastatur-unabhängigen Standard-Pfad** über Carbon `RegisterEventHotKey`
  (⌘/⌃/⌥/⇧ + Taste) mit generischem `NSEvent`-Monitor-Fallback – so zünden Trigger
  auch auf Fremdtastaturen wie der **KB066**, die kein systemweites fn-Event senden.
  Pro Zeile: aktuelle Kombi-Anzeige, „Aufnehmen“-Picker (fängt den nächsten
  Tastendruck ab, ESC bricht ab), Checkbox „fn verwenden“, Konfliktprüfung (kein
  Doppelbelegen) sowie ein globaler „Auf Standard zurücksetzen“-Button. Änderungen
  werden ohne App-Neustart neu registriert. Version 1.5 → 1.6.
- **CI: macOS-Release-Build als ladbares Artefakt** (SE-T-615, Phase 1). Der Job
  `build-macos` baut jetzt die **Release-`.app`** (universal x86_64 + arm64),
  prüft per `lipo` hart auf beide Architekturen, zippt das Bundle via `ditto`
  (`Blitztext-<version>.zip`, Version aus dem gebauten `Info.plist`
  `CFBundleShortVersionString`, Fallback `dev`) und lädt es als Artefakt
  `blitztext-mac-app` hoch (Aufbewahrung 14 Tage). Neuer manueller Trigger
  `workflow_dispatch` ergänzt die bestehenden push/pull_request-Trigger.
  Unsigniert/ad-hoc (kein Signing/Notarisierung in dieser Phase).
