# Speedy Boy v2.0

Cross-platform speed reading app with a 3D neumorphic cube viewport and optional stereoscopic head-tracking.

## Prerequisites

- **Flutter SDK** ≥ 3.5.3 ([install](https://docs.flutter.dev/get-started/install))
- **Dart SDK** ≥ 3.5.3 (bundled with Flutter)
- Platform toolchains for your target (see below)

## Setup

```bash
flutter pub get
```

## Running in Debug / Dev Mode

### Windows Desktop

Requires Visual Studio 2022 with the "Desktop development with C++" workload.

```bash
flutter config --enable-windows-desktop
flutter run -d windows
```

### macOS Desktop

Requires Xcode 15+.

```bash
flutter config --enable-macos-desktop
flutter run -d macos
```

### Linux Desktop

Requires `clang`, `cmake`, `ninja-build`, `pkg-config`, `libgtk-3-dev`.

```bash
flutter config --enable-linux-desktop
flutter run -d linux
```

### Android

Requires Android Studio with an emulator or a connected device with USB debugging enabled.

```bash
flutter run -d <device-id>
```

To list available devices:

```bash
flutter devices
```

#### Android Emulator (`flutter_emu`)

Start the emulator in the background:

```bash
emulator -avd flutter_emu &
```

Wait for it to fully boot, then run the app:

```bash
adb wait-for-device && flutter run -d emulator-5554
```

**Cold boot** (required after AVD config changes):

```bash
emulator -avd flutter_emu -no-snapshot-load &
```

**Save a fresh snapshot** (after a clean boot you're happy with):

```bash
adb emu avd snapshot save default_boot
```

**Common ADB commands:**

```bash
adb devices                                         # list connected devices/emulators
adb logcat -s flutter                               # stream Flutter logs only
adb shell wm size                                   # check screen resolution
adb shell wm density                                # check screen DPI
adb shell am force-stop com.speedyboy.speedy_boy    # kill the app
adb uninstall com.speedyboy.speedy_boy              # uninstall the app
```

**Wipe emulator data** (factory reset):

```bash
emulator -avd flutter_emu -wipe-data
```

AVD config: `%USERPROFILE%\.android\avd\flutter_emu.avd\config.ini`

#### MuMu Player (Android emulator)

[MuMu Player](https://www.mumuplayer.com/) is a performant Android emulator for Windows useful for testing when AVD is slow or unavailable.

**Connect ADB to MuMu:**

```bash
adb connect 127.0.0.1:7555
```

> MuMu Player 12 uses port `16384` by default. Check MuMu's settings → ADB for the correct port.

**Verify connection:**

```bash
adb devices
# Should show: 127.0.0.1:7555  device
```

**Run the app on MuMu:**

```bash
flutter run -d 127.0.0.1:7555
```

**Tips:**

- Enable **Root permission** in MuMu settings if you need `adb root` access.
- Set display resolution to a phone-like size (e.g. 1080×2400) in MuMu's display settings for realistic testing.
- If `adb connect` fails, ensure MuMu is fully booted and ADB debugging is enabled in MuMu settings.
- If Flutter can't find the device, run `adb kill-server && adb start-server` then reconnect.
- Hot reload (`r`) and hot restart (`R`) work normally once connected.

### iOS

Requires Xcode 15+ and a valid signing identity. Simulator works for debug.

```bash
open ios/Runner.xcworkspace   # set signing team in Xcode first
flutter run -d <device-id>
```

### Chrome (Web) — experimental

```bash
flutter run -d chrome
```

## Useful Commands

| Command | Description |
|---|---|
| `dart analyze lib/` | Static analysis (strict mode) |
| `flutter test` | Run unit tests |
| `flutter test integration_test/` | Run integration tests |
| `flutter run -d windows --release` | Release build (Windows) |
| `flutter build apk` | Release APK (Android) |
| `flutter build ios` | Release build (iOS) |

## AI Tooling Parity Check

Run this to verify Claude/Codex parity for shared instructions, MCP wiring, plugins/skills baseline, and shared agent files:

```bash
scripts/verify_ai_parity.sh
```

## Hot Reload / Hot Restart

While the app is running in debug mode, press:

- **r** — Hot reload (preserves state)
- **R** — Hot restart (resets state)
- **q** — Quit

## Full Screen Mode

On **Windows**, **macOS**, and **Linux**: click the full-screen icon (top-right) in the reading view, or press **F11** (OS-level) to toggle full-screen. This hides the title bar and system chrome for a distraction-free, immersive reading experience with the magic window parallax effect.

## Project Structure

```
lib/
  core/         # ORP algorithm, word timer, dynamic font sizing
  design/       # Design tokens, typography, decorations, materials, animations
  hooks/        # Bookmark auto-save notifier
  navigation/   # go_router config + cube transition
  screens/      # Library, Reading, Settings screens
  services/     # PDF extraction, folder scanning, preprocessing queue
  stereo/        # Optional magic window parallax (pointer/IMU-driven)
  store/        # Riverpod state (config, models)
  three_d/      # Cube viewport painter, word painter, glyph measurer
  widgets/      # Reusable 3D neumorphic widgets
  debug/        # Latency & FPS probes (debug builds only)
test/           # Unit tests
integration_test/ # Integration tests
```

## Architecture

- **State**: Riverpod (`flutter_riverpod`)
- **Navigation**: go_router with 3D cube rotation transitions
- **Rendering**: CustomPainter + Canvas + Matrix4 for the 3D cube viewport
- **PDF**: Syncfusion PDF extraction in Dart Isolates
- **Head Tracking**: Optional — pointer-driven magic window parallax (desktop mouse hover), IMU/gyro (mobile). Creates an AR-like illusion of looking into the device. Graceful no-op when disabled.
