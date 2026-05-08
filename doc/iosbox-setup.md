# iOS Testing on Windows via iosbox

Build RunThru for a real iPhone from Windows — no Mac required.

> **Scope:** local development testing only. App Store / TestFlight releases still
> use Codemagic (see `codemagic_appstore_workflow.md`). iosbox produces **debug,
> unsigned** IPAs.

## Pipeline

```
Windows + Docker         iPhone
┌──────────────────┐     ┌────────────────┐
│ iosbox build     │ ──► │ Sideloadly /   │
│ → Runner.ipa     │     │ AltStore /     │
│   (unsigned)     │     │ MobAI signs +  │
└──────────────────┘     │ installs       │
                         └────────────────┘
```

## One-time setup

### 1. Download Xcode 26.3

- Sign in at <https://developer.apple.com/download/all/?q=xcode%2026.3> with a free Apple ID.
- Download `Xcode_26.3_Apple_silicon.xip` (or Universal). Save anywhere (e.g. `C:\xcode\`).
- ⚠️ **Xcode 26.4+ is NOT supported** by iosbox (SDK header stubs).
- Browser session required — `curl` won't work without auth cookies.

### 2. Pull image + extract SDK

```powershell
docker pull mobaiapp/iosbox:flutter-3.41.0
./scripts/iosbox-build.ps1 -Setup -XcodeXip C:\xcode\Xcode_26.3_Apple_silicon.xip
```

This populates the `iosbox-sdk` Docker volume (~30 GB). Done once.

### 3. Install a sideloader on Windows

Pick one for the sign + install step:

| Tool | Cost | Refresh cadence | Notes |
|---|---|---|---|
| **Sideloadly** | Free | 7 days (free Apple ID) | Easiest. USB cable. <https://sideloadly.io> |
| **AltStore PAL / AltServer** | Free | 7 days | Wi-Fi refresh. Linux-friendly. |
| **MobAI** | Paid | Per their plan | OTA install, made by iosbox authors. <https://mobai.run> |

Free Apple ID limits: 3 apps signed at once, 7-day expiry, USB refresh required.

## Building

```powershell
./scripts/iosbox-build.ps1
```

Output: `build/iosbox/Runner.ipa`.

## Installing on iPhone (Sideloadly path)

1. Connect iPhone via USB. Trust this computer.
2. Open Sideloadly, drag `build/iosbox/Runner.ipa` in.
3. Enter Apple ID + app-specific password.
4. On iPhone: Settings → General → VPN & Device Management → trust your developer profile.
5. Launch RunThru.

## Known risks for RunThru specifically

iosbox replaces CocoaPods with Swift Package Manager. Every iOS plugin must
support SwiftPM. RunThru's iOS plugins (from `pubspec.yaml`):

| Plugin | SwiftPM status | Risk |
|---|---|---|
| pdfrx | Has SwiftPM (`pdfrx` 2.x) | Low — but pulls pdfium binary |
| file_picker | SwiftPM supported | Low |
| permission_handler | SwiftPM supported (recent) | Low |
| path_provider | SwiftPM supported | Low |
| shared_preferences | SwiftPM supported | Low |
| flutter_secure_storage | SwiftPM supported | Low |
| device_info_plus | SwiftPM supported | Low |
| url_launcher | SwiftPM supported | Low |

**Highest risk:** the iOS **Share Extension** (`ios/ShareExtension/`). iosbox
generates `Package.swift` for the Runner target. If the Share Extension target
needs separate handling, the IPA may build without the extension or fail
linking. This is the first thing to verify on the first build.

## Limitations

- **Debug builds only** (no AOT/release yet). Performance on iPhone will be
  noticeably slower than a release build — sufficient for UX testing,
  insufficient for benchmarking pacing engine FPS.
- **Physical devices only** (`arm64-apple-ios`). No simulator.
- **Xcode 26.3 ceiling.** Will need re-evaluation when iosbox supports newer.
- **Flutter 3.41.0** in the image vs **3.41.6** locally. Patch-level mismatch
  is usually fine. If issues, run `flutter downgrade 3.41.0` locally before
  comparing behaviour.

## Troubleshooting

### "Plugin X does not support SwiftPM"
Check the plugin's repo for a `Package.swift`. If missing, options:
1. Pin to a newer version that adds SwiftPM (`flutter pub upgrade <plugin>`).
2. Fork + add SwiftPM support (pattern documented in Flutter SwiftPM docs).
3. Remove the plugin temporarily for iPhone test builds (use a feature flag).

### Share Extension missing from installed app
Expected on first attempt. Workarounds:
- For pure reading-flow testing, install the IPA without the extension and
  paste content via clipboard (RunThru auto-detects clipboard).
- For Share Extension testing specifically, fall back to Codemagic.

### Build cache corrupt
```powershell
docker volume rm iosbox-swift-cache-runthru iosbox-build-cache-runthru
./scripts/iosbox-build.ps1
```

(Don't delete `iosbox-sdk` — that's the 30 GB Xcode extract.)

## When to use what

| Goal | Tool |
|---|---|
| "Does my latest change work on iPhone?" | iosbox + Sideloadly |
| "Does the Share Extension flow work?" | Codemagic (build + TestFlight internal) |
| "Ship to App Store" | Codemagic (`codemagic_appstore_workflow.md`) |
| Performance / FPS validation | Codemagic release build → TestFlight |
