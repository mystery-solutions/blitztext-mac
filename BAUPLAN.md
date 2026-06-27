# Bauplan Blitztext (KI-Stratege Mac-Variante)

Eigener Fork von cmagnussen/blitztext-app. Hier bauen wir unsere KI-Stratege-Variante.

## Repos
- macOS (dieses Repo): github.com/mystery-solutions/blitztext-mac (Fork, Swift/Xcode)
- Windows: github.com/mystery-solutions/blitztext-win (Tauri, eigener Codebase)
- upstream-Remote: cmagnussen/blitztext-app (nur fuer gelegentliche Merges)

## Build macOS (lokal, Entwicklung)
Voraussetzung: Mac mit Xcode + xcodegen (brew install xcodegen).

    cd ~/_code/blitztext-mac
    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer bash build.sh

Erzeugt Blitztext.app (Universal x86_64+arm64). Danach nach /Applications kopieren oder zippen.

## Build macOS (CI, Release) - geplant SE-T-615
GitHub Actions macOS-Runner baut die .app, laedt sie als Artefakt hoch, danach
Spiegelung in den Supabase-Bucket mit signierter Download-URL (analog Windows).
Vorteil: kein lokaler Mac noetig, reproduzierbar.

## Warum eigene Pipeline (nicht VPS-Docker)
Swift/Xcode baut NUR auf macOS, nicht auf dem Linux-VPS. Blitztext-Mac laeuft daher
nicht ueber die normale VPS-Docker-Deploy-Strecke der Web-Apps, sondern ueber GitHub
Actions (Mac-Runner) plus Bucket-Download. Dispatch-Routing: roadmap=blitztext.

## Upstream-Sync
    git fetch upstream && git merge upstream/main   # Konflikte mit unseren Anpassungen pruefen

## Eigene Anpassungen (Roadmap)
- SE-T-714: konfigurierbarer Hotkey-Picker pro Workflow (Standard-Modifier statt fn-Zwang)
- weitere folgen
