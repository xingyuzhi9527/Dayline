# Liflow Android Build and Device Install Rules

These rules apply to Android APK builds and real-device installation for this
Flutter project.

## Toolchain

- Flutter SDK: `C:\flutter`
- Flutter command on this machine: `C:\flutter\bin\flutter.bat`
- Android SDK: `E:\Androidsdk`
- ADB: `E:\Androidsdk\platform-tools\adb.exe`
- Application ID: `com.example.liflow_app`

## Release Signing

- Release builds must use the existing production signing configuration in
  `android/key.properties` and `android/dayline-release.jks`.
- The Android Gradle configuration is fail-closed. Never replace the production
  signing key with a debug key or generate a new key for an update build.
- Before delivery, verify every APK with the Android build-tools `apksigner`.
- Expected signing certificate SHA-256 fingerprint:
  `09855f20249d8c1248e7d49fe0c675fde649ad9dc75a15e95ce4dcc4f09940b6`.

## Build Separate APKs

Every release build must use a new Android build number. The current delivered
version is `2.0.0+11`; the next release must be `2.0.0+12`.

Use the release wrapper so the build number is incremented exactly once before
the build, and the versioned APK copies are created automatically:

```powershell
& '.\tool\build_release.ps1' -NoPub
```

The wrapper restores the previous `pubspec.yaml` version if the build fails.
Do not reuse an old versioned APK or run the raw Flutter release command for a
new delivery unless the build number has first been incremented manually.

The underlying Flutter command is:

```powershell
& 'C:\flutter\bin\flutter.bat' build apk --release --split-per-abi --no-pub
```

The outputs are:

- `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` for most modern
  Android phones.
- `build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk` for 32-bit ARM
  devices.
- `build/app/outputs/flutter-apk/app-x86_64-release.apk` for x86-64 devices and
  emulators.

For delivery, use the wrapper's versioned copies, for example
`Liflow-v2.0.0-build12-arm64-v8a-release.apk`, without changing the original
Flutter output names.

## Verify and Install

1. Check the device before attempting installation:

   ```powershell
   & 'E:\Androidsdk\platform-tools\adb.exe' devices -l
   ```

2. Prefer `arm64-v8a` for a modern physical phone. Install with replacement
   and runtime permission grants:

   ```powershell
   & 'E:\Androidsdk\platform-tools\adb.exe' -s <DEVICE_ID> install -r -g `
     build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
   ```

3. Do not run `flutter install` for upgrade testing because it may uninstall the
   existing app and risk local data. Do not uninstall before an update unless
   the user explicitly asks for a clean-data test.

4. Confirm the installed package and version after installation:

   ```powershell
   & 'E:\Androidsdk\platform-tools\adb.exe' -s <DEVICE_ID> shell pm path com.example.liflow_app
   & 'E:\Androidsdk\platform-tools\adb.exe' -s <DEVICE_ID> shell dumpsys package com.example.liflow_app
   ```

5. If no device is listed, finish the build and verification, report that the
   device is not connected, and do not claim that installation succeeded.

## Delivery Checklist

- Run `flutter analyze --no-pub` when practical.
- Build with `--release --split-per-abi`.
- Report each APK path, size, and SHA-256.
- Verify APK signatures and the expected certificate fingerprint.
- Install only the matching ABI with `adb install -r -g`.
- Preserve the existing app data during upgrade testing.
