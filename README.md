# Liflow

> A local-first life record app for quick capture, personal timeline, projects, and daily review.

Liflow is an Android-first Flutter app for people who want to record their day without turning private life data into a cloud product. It keeps notes, voice captures, todos, project progress, review drafts, photos, and exported Markdown files on the device, with no account system, no ads, no analytics SDK, and no cloud sync service wired into the app.

[Download release APK](https://github.com/2478643035/Dayline/releases/download/v2.0.0-build9/Liflow-v2.0.0-build9-release.apk) · [Release page](https://github.com/2478643035/Dayline/releases/tag/v2.0.0-build9)

Current version: `2.0.0+9`

## What Liflow Does

Liflow is built around four daily surfaces:

- `记`: capture a thought immediately with voice or text. Voice recognition is designed to run locally on Android through the bundled offline STT assets.
- `线`: turn scattered captures into a chronological life timeline, including notes, todos, long notes, photos, and recoverable deleted items.
- `项`: keep personal projects moving with project cards, progress, todos, and recent updates.
- `盘`: review the day, inspect rhythm and unfinished work, and draft a daily reflection that can be saved as Markdown.

The product idea is simple: record quickly, organize lightly, review gently, and keep the raw material readable outside the app.

## Local-First Data Model

Liflow stores structured data in local SQLite and mirrors user-facing knowledge into a visible `Liflow` folder. On Android, the app asks the user to choose or confirm a local document folder, then keeps core directories such as:

```text
Liflow/
  daily/
  notes/
  documents/
  projects/
```

This makes the app easier to trust:

- data remains on the device by default;
- Markdown files can be inspected without opening the app;
- records can be restored from the local folder when the database is empty;
- photos and audio attachments are kept as local files;
- release builds can be installed directly from GitHub Releases.

## Privacy Position

Liflow does not include login, advertising, analytics, tracking SDKs, or cloud synchronization. The microphone permission is used for local recording and offline speech recognition. The app may request Android platform permissions required by Flutter, recording, file access, or Bluetooth/audio behavior, but the current app code is not connected to a remote Liflow service.

Because this is a local-first app, users should still back up their chosen `Liflow` folder if they care about long-term preservation.

## Feature Highlights

- Fast voice/text capture from the center `记` screen.
- Offline Chinese speech recognition assets bundled under `assets/stt/`.
- Lightweight parsing for todos, time hints, amounts, and memo context.
- Timeline browsing with SQLite-backed records.
- Long-note editor and Markdown reader.
- Project workspace with local Markdown persistence.
- Daily dashboard and review writer.
- Local backup snapshot and restore flow.
- Photo moments and local document library.
- Android release signing support through local `android/key.properties`.

## Tech Stack

- Flutter `>=3.35.0`
- Dart `^3.9.0`
- Riverpod for app state and dependency injection
- GoRouter with an indexed shell route for the main tabs
- SQLite through `sqflite`
- `sherpa_onnx` for local speech recognition
- `record` for audio recording
- Markdown/local file services for readable exports and restore

## Repository Layout

```text
lib/
  core/
    database/     SQLite schema and repositories
    markdown/     local Markdown paths, persistence, restore helpers
    media/        audio, playback, and photo services
    parser/       lightweight life-input parsing
    stt/          local speech-to-text integration
    theme/        color, spacing, typography tokens
  features/
    flash_record/ quick record screen
    timeline/     chronological record view
    projects/     project workspace
    dashboard/    daily review dashboard
    long_note/    long-form notes
    documents/    local document library
    restore/      Markdown restore flow
android/
  app/            Android application shell and release signing config
assets/
  stt/            offline STT model assets and keywords
test/             widget, repository, parser, STT, and feature tests
```

## Install

For a normal Android install, download the signed release APK:

```text
https://github.com/2478643035/Dayline/releases/download/v2.0.0-build9/Liflow-v2.0.0-build9-release.apk
```

The current APK is large because it bundles offline speech-recognition assets.

## Development

Install Flutter, then run:

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

To build a release APK locally:

```bash
flutter build apk --release
```

Release signing is read from `android/key.properties`, which is intentionally ignored by Git. A local file should provide:

```properties
storePassword=...
keyPassword=...
keyAlias=...
storeFile=...
```

The signed APK is produced at:

```text
build/app/outputs/flutter-apk/app-release.apk
```

## Release

Latest release:

- Tag: `v2.0.0-build9`
- Commit: `ed4680c`
- APK: `Liflow-v2.0.0-build9-release.apk`
- SHA-256: `A742544FAD085A1AA50559712162CA78C976975C4A18025ADEA7E44A2508FDFB`

## Notes

The repository name is still `Dayline`, while the current Android app label and product direction use `Liflow`.
