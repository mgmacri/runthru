# Android Build and Emulator Runbook

RunThru's Android application ID is `com.runthru.app`. The iOS bundle IDs are
intentionally different; do not change either platform to match the other.

## Local Build Prerequisites

- Flutter SDK available to `flutter`.
- Android SDK available through `ANDROID_SDK_ROOT`.
- JDK 17 or newer. This repo pins Gradle to Android Studio's bundled JBR through
  `android/gradle.properties`.
- Writable Gradle and pub caches.

On Arch/AUR Flutter installs, `/usr/lib/flutter` is not writable. The Android
settings file mirrors Flutter's Gradle plugin from:

```sh
/usr/lib/flutter/packages/flutter_tools/gradle
```

into the project-local ignored path:

```sh
android/.gradle/flutter_gradle
```

Gradle includes that writable copy so Kotlin/Gradle session files are not
written under the Flutter SDK. The mirror is deterministic and safe to rerun.

## Known-Good Local Build Commands

```sh
flutter pub get
dart analyze --fatal-infos
flutter test
flutter build apk --debug
flutter build appbundle --release
```

If `android/key.properties` is missing, local release builds fall back to debug
signing so the AAB can still be produced for validation. Google Play uploads
must use the real upload keystore.

## Stable Emulator Startup

Prefer a cold, software-rendered emulator session when the AVD has snapshot or
GPU instability:

```sh
emulator -avd runthru_api36 -gpu swiftshader_indirect -no-snapshot
```

Use `-verbose` when diagnosing boot failures:

```sh
emulator -avd runthru_api36 -gpu swiftshader_indirect -no-snapshot -verbose
```

## ADB and Package Manager Health Checks

Run these before installing if the emulator has recently hung or `flutter run`
cannot connect:

```sh
adb devices -l
adb shell true
adb shell pidof system_server
adb shell cmd package resolve-activity --brief com.runthru.app
```

`adb shell pidof system_server` must print a PID. If `cmd package` reports that
the package service cannot be found, Android's `system_server` or package
manager is unhealthy; restart the emulator before retrying install.

## Install and Launch

```sh
flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb shell cmd package resolve-activity --brief com.runthru.app
flutter run -d emulator-5554 -v
```

If `adb install -r` hangs, check package manager health again before assuming
the APK is bad.

## Non-Destructive Emulator Recovery

These commands do not wipe AVD user data:

```sh
adb devices -l
adb kill-server
adb start-server
adb devices -l
adb emu kill
emulator -avd runthru_api36 -gpu swiftshader_indirect -no-snapshot
```

Only wipe emulator data after confirming the same AVD fails after a cold
software-rendered boot and ADB/package-manager restart.

## Codemagic Android Secrets

The Android Codemagic workflow expects:

- Codemagic Android code signing reference: `runthru_upload_keystore`
- Environment group: `google_play_credentials`
- `GOOGLE_PLAY_SERVICE_ACCOUNT_CREDENTIALS`: Google Play service account JSON
  content for publishing.

Codemagic injects these signing variables from the signing reference:

- `CM_KEYSTORE_PATH`
- `CM_KEYSTORE_PASSWORD`
- `CM_KEY_ALIAS`
- `CM_KEY_PASSWORD`

The workflow writes `android/key.properties` at build time from those injected
values. Do not commit `key.properties`, `.jks`, or `.keystore` files.
