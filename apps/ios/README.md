# TODO_AI — iOS / iPadOS

SwiftUI app. Open `TODO_AI/TODO_AI.xcodeproj` (created with Xcode 27 beta —
project format 110 requires it; build via CLI with
`DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild …`).
The project uses synchronized folders: files added on disk appear in the target
automatically.

## Structure (`TODO_AI/TODO_AI/`)

- `TODO_AIApp.swift` — app entry: onboarding gate + tab shell
- `Features/` — Chat · History (+ day timeline) · Settings (+ sub-screens) · Onboarding · MainTabView
- `Core/` — DesignSystem (Linear midnight tokens), API client, Keychain,
  GoogleAuth (ASWebAuthenticationSession), Notifications, Time helpers
- `Resources/Fonts/` — Inter + JetBrains Mono (OFL), registered at runtime

## Backend

Simulator talks to `http://127.0.0.1:8000`; physical devices go through the
ngrok tunnel (see `Core/API.swift`). Start the backend per `apps/api/README.md`.
