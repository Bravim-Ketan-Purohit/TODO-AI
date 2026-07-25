# TODO_AI

AI-native day planner for iOS & iPadOS. Type your day in plain English; it becomes
color-coded events on your Google Calendar, scheduled around what's already there.

See [`docs/spec.md`](docs/spec.md) for the full product + tech spec.

## Structure

```
apps/
  ios/   SwiftUI app (iOS + iPadOS)
  api/   FastAPI backend — LLM proxy + Google Calendar broker
docs/    spec, design system, design prompt
```

## Running

- **Backend:** [`apps/api/README.md`](apps/api/README.md)
- **iOS app:** [`apps/ios/README.md`](apps/ios/README.md)
