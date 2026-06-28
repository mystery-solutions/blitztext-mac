# Changelog — Blitztext (macOS)

Format orientiert an [Keep a Changelog](https://keepachangelog.com/de/).

## [Unreleased]

### Hinzugefügt
- **CI: macOS-Release-Build als ladbares Artefakt** (SE-T-615, Phase 1). Der Job
  `build-macos` baut jetzt die **Release-`.app`** (universal x86_64 + arm64),
  prüft per `lipo` hart auf beide Architekturen, zippt das Bundle via `ditto`
  (`Blitztext-<version>.zip`, Version aus dem gebauten `Info.plist`
  `CFBundleShortVersionString`, Fallback `dev`) und lädt es als Artefakt
  `blitztext-mac-app` hoch (Aufbewahrung 14 Tage). Neuer manueller Trigger
  `workflow_dispatch` ergänzt die bestehenden push/pull_request-Trigger.
  Unsigniert/ad-hoc (kein Signing/Notarisierung in dieser Phase).
