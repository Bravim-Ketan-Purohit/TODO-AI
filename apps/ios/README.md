# TODO_AI — iOS / iPadOS

SwiftUI app. Source lives in `TODO_AI/`. The `.xcodeproj` is created in Xcode
(only user-specific bits are gitignored, so committing the project is fine).

## First-time setup

1. Xcode → File > New > Project > App (SwiftUI, iOS), name it `TODO_AI`, save here (`apps/ios/`).
2. Remove Xcode's default `ContentView.swift` and generated App file.
3. Drag the existing `TODO_AI/` source folder into the project (add as group references).

## Structure

- `TODO_AIApp.swift` — app entry: onboarding gate + tab bar
- `Features/` — Chat · History · Settings · Onboarding
- `Core/` — networking, models (added as needed)
- `Resources/` — assets
