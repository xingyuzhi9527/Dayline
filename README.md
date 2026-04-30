# Dayline

Dayline is a local-first Flutter life record app skeleton. The first iteration
contains the app shell, Riverpod setup, GoRouter bottom-tab routing, theme
tokens, and a SQLite database entry point.

## Current scope

- Four bottom tabs: Today, Record, Timeline, Review
- Material 3 light and dark themes
- Central color, typography, and spacing constants
- Riverpod `ProviderScope` at the app root
- GoRouter `StatefulShellRoute.indexedStack` navigation
- SQLite storage via `sqflite`

Drift is preferred for the full persistence layer, but this workspace does not
currently have Flutter/Dart available, so code generation cannot be configured
or verified here. The SQLite layer uses `sqflite` as the requested fallback.

## Verification

Run these commands from this directory after installing Flutter:

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

No network, login, ads, analytics, or tracking SDKs are included.
