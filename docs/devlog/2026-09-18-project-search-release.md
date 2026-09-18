# Liflow 2.0.0+11 - 2026-09-18

## Updates

- Add search to the Projects page, initially scoped to the selected project.
- Show the selected project filter and allow clearing it to search across projects.
- Preserve search terms and filters when returning from a result; isolate project and dashboard search sessions.
- Read project images from the selected document folder, cache bounded thumbnails, and preserve portable image references during backup and restore.
- Avoid duplicate daily-note reads and improve generation feedback and retry behavior.

Search currently covers project names and associated records. It does not add full-text search of attached documents.

## APKs

The APKs retain versionName 2.0.0 and base build number 11. The ARM64 APK versionCode is 2011, unchanged from the July ARM64 release. This dated release tag distinguishes the updated binaries.

- `app-arm64-v8a-release.apk`: recommended for most Android phones.
- `app-armeabi-v7a-release.apk`: for 32-bit ARM devices.
- `app-x86_64-release.apk`: for x86-64 devices and emulators.

Application ID: `com.example.liflow_app`.

All APKs passed APK Signature Scheme v2 verification. The signing certificate matches the July 19 ARM64 APK. Install over the existing app to retain its data; do not uninstall first.

Certificate SHA-256: `09855f20249d8c1248e7d49fe0c675fde649ad9dc75a15e95ce4dcc4f09940b6`.

## Validation

- `flutter analyze --no-pub`: no issues.
- `flutter test --no-pub`: 340 tests passed.
- `flutter build apk --release --split-per-abi --no-pub`: succeeded.
- Small-screen search tested at 320dp with 1.3x text scaling.
- APKs have not been installed on a phone in this release workflow.

## APK SHA-256

| File | SHA-256 |
| --- | --- |
| app-arm64-v8a-release.apk | B55630BE493BECE42861B66FFB3B6B2D3D5DE607E551EED8C1392D78525AA81E |
| app-armeabi-v7a-release.apk | F9C92BCA1E2566FDEA8D913BADAD447065CF1A2D2E0C00660AD4EC84BF4430EE |
| app-x86_64-release.apk | 89A3D67353F50F0BC9A195A3AB4CF3134338FF5673F0C448FE3BD131A1BB18ED |
