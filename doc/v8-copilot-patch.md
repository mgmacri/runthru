# Speedy Boy — Copilot Instructions v8 Patch

Apply these changes to `.github/copilot-instructions.md` on top of the existing v4 + v6 + v7 content.
v5 was a removal release (no new rules). v6 added rules 29–34. v7 added rules 35–42. v8 adds rules 43–49.

---

## New Rules (43–49)

43. **Share intents drain BEFORE `runApp()`.** `ShareIntentService.drainInitialPayload()` is the first awaited call in `main()`, before `runApp()`. The drained `SharedPayload?` is stored in a top-level provider and dispatched via `WidgetsBinding.instance.addPostFrameCallback` after the navigator mounts. Never attempt to navigate from a share payload before the first frame.

44. **Cold-start and warm-start payloads must never both fire.** The native bridge (Android `MainActivity`, iOS `AppDelegate`) marks the cold-start payload as consumed before the warm-start stream begins emitting. The Dart layer must not implement separate dedup — trust the native contract. If both fire, the bug is on the native side and must be fixed there.

45. **Shared URL fetching is NEVER automatic for untrusted domains.** Untrusted URLs ALWAYS go through `SharePreviewSheet` for explicit user confirmation. The trusted-domain allowlist lives in `AppConfig.trustedShareDomains` and is the only path to auto-fetch. Per DP4 — no silent network calls.

46. **Share payload contents NEVER appear in logs.** Log only metadata: `kind`, `sourceAppId`, `hasText` (bool), `hasUrl` (bool), fetch latency, success/failure. The text body, the URL itself (with or without query params), and the subject line MUST NOT be logged. URLs are particularly sensitive — they often contain auth tokens. This is the v7 P19/Rule 36 posture extended to share intents.

47. **Shared text is ephemeral. Shared URLs are persisted (capped FIFO).** Text shares produce `ClipboardDocument` instances and follow Rule 28 (no library persistence). URL shares are written to `SharedUrlCache` (`<appSupport>/shared_url_cache/`) and surfaced in the library's "Recently Shared" section, capped at `AppConfig.recentlySharedCap` entries (default 20, range [5, 100]) with FIFO eviction. Per DP6.

48. **URL fetching reuses v6's InstaparserService and HtmlTextExtractor unchanged.** Do not create a parallel HTTP fetch path. Do not create a parallel HTML parser. Shared URLs and Instapaper URLs share the same extraction pipeline. If `InstaparserService` needs a new method, add it to `InstaparserService` — do not branch into a `SharedUrlExtractorService`. Per DP2.

49. **Share intent during active reading shows a snackbar, not a takeover.** If the user is in `ParallaxReadingScreen` (any source) when a share payload arrives via the warm stream, `ShareIntentRouter` shows a snackbar with [Read now][Save for later][Dismiss] actions. It must never replace the active reading screen without user choice. Per DP1's "respect the user's current task" corollary.

---

## New Design System Files (v8)

```
lib/services/share_intent_service.dart       → ShareIntentService (Dart facade)
lib/services/share_intent_router.dart        → ShareIntentRouter (decision logic)
lib/services/shared_url_cache.dart           → SharedUrlCache (persistence)
lib/models/shared_payload.dart               → SharedPayload + SharedPayloadKind enum
lib/models/shared_url_entry.dart             → SharedUrlEntry model
lib/screens/share_receive_screen.dart        → ShareReceiveScreen (cold-start landing)
lib/widgets/share_preview_sheet.dart         → SharePreviewSheet (modal bottom sheet)
lib/widgets/recently_shared_section.dart     → RecentlySharedSection (library section)
lib/providers/share_intent_provider.dart     → shareIntentProvider, recentlySharedProvider (Riverpod)
android/app/src/main/AndroidManifest.xml     → MODIFY: add ACTION_SEND intent-filter
android/app/src/main/kotlin/.../MainActivity.kt → MODIFY: read intent + push to method channel
ios/Runner/AppDelegate.swift                  → MODIFY: handle speedyboy:// URL scheme
ios/Runner/Info.plist                         → MODIFY: register URL scheme + App Group
ios/SpeedyBoyShareExtension/                  → NEW iOS target (extension)
ios/SpeedyBoyShareExtension/ShareViewController.swift → Extension entry point
ios/SpeedyBoyShareExtension/Info.plist        → Extension manifest
ios/SpeedyBoyShareExtension/SpeedyBoyShareExtension.entitlements → App Group entitlement
```

---

## New AppConfig Fields (v8)

```dart
final bool universalShareEnabled;             // default: true
final List<String> trustedShareDomains;       // default: see seed list
final int recentlySharedCap;                  // default: 20, clamp [5, 100]
```

### Trusted Domain Seed List

```dart
const _defaultTrustedShareDomains = [
  'medium.com',
  'substack.com',
  'nytimes.com',
  'theguardian.com',
  'arstechnica.com',
  'wired.com',
  'theatlantic.com',
  'newyorker.com',
  'washingtonpost.com',
  'bloomberg.com',
];
```

Wildcard subdomain support: a stored entry of `*.substack.com` matches any subdomain. Stored entries without `*.` are exact-match only.

### New ConfigNotifier Methods

```dart
Future<void> setUniversalShareEnabled(bool enabled);
Future<void> addTrustedShareDomain(String domain);
Future<void> removeTrustedShareDomain(String domain);
Future<void> setRecentlySharedCap(int cap);  // clamp inside method
```

---

## New Enums (v8)

```dart
// in lib/models/shared_payload.dart
enum SharedPayloadKind { text, url, mixed, empty }
```

---

## Updated Route Map (v8)

| Route | Screen | Params | Notes |
|---|---|---|---|
| `/` | HomeShell (library) | `?tab=N` | Unchanged |
| `/read` | ParallaxReadingScreen | `filePath` (PDF) | Unchanged |
| `/read-legacy` | ReadingScreen | `filePath` | Unchanged |
| `/read-clipboard` | ParallaxReadingScreen | `extra: ClipboardDocument` | Unchanged |
| `/read-instapaper` | ParallaxReadingScreen | `extra: InstapaperBookmark` | v6 |
| `/share-receive` | ShareReceiveScreen | — | **NEW** — cold-start landing |
| `/share-preview` | SharePreviewSheet (modal) | `extra: SharedPayload` | **NEW** |
| `/read-shared-url` | ParallaxReadingScreen | `?hash=<urlHash>` | **NEW** |
| `/range-picker` | RangePickerScreen | `filePath` | Unchanged |
| `/settings` | `/?tab=3` redirect | — | Unchanged |

---

## New Constants (in `SpeedyBoyTiming`)

```dart
// ── v8: Universal Share ──
static const int sharePreviewBannerDurationMs = 1500;  // trusted-domain auto-confirm
static const int shareReceiveScreenTimeoutMs = 5000;   // hard timeout before showing error
static const int shareSheetEnterMs = 250;              // matches assistantSheetEnterMs
static const int shareSheetExitMs = 200;
static const int shareSnackbarDurationMs = 6000;       // snackbar shown during active reading
```

---

## New Constants (in `SpeedyBoyGestures`)

```dart
// v8 — share preview sheet dismiss matches v7 assistant sheet
static const double sharePreviewDismissVelocity = 300.0;  // px/sec swipe-down
```

---

## Updated Skill Mapping (v8 additions)

| Domain | Skill File | v8 Tasks |
|---|---|---|
| Platform channels | `flutter-using-platform-channels` | Native bridge for share intents (Android + iOS) |
| HTTP/networking | `flutter-handling-http-and-json` | URL article fetch (reuses v6 service) |
| Concurrency | `flutter-handling-concurrency` | Share cache I/O in Isolates, payload draining |
| State management | `riverpod-providers` | shareIntentProvider, recentlySharedProvider |
| Riverpod auto-dispose | `riverpod-auto-dispose` | SharePreviewSheet state cleanup |
| Layout | `flutter-building-layouts` | SharePreviewSheet, RecentlySharedSection, ShareReceiveScreen |
| Forms/controls | `flutter-building-forms` | Trusted-domain editor in Settings |
| Navigation | `flutter-implementing-navigation-and-routing` | New share routes, cold-start dispatch |
| Animation | `flutter-animating-apps` | Sheet enter/exit, banner slide-in |
| Theming | `flutter-theming-apps` | ShareReceiveScreen + sheet surface compliance |
| Accessibility | `flutter-improving-accessibility` | Sheet semantics, screen reader for preview cards |
| Testing | `flutter-testing-apps` + `riverpod-testing` | Service mocks, router decision table coverage |
| Working with databases | `flutter-working-with-databases` | AppConfig persistence for new fields, SharedUrlCache |
| Caching | `flutter-caching-data` | SharedUrlCache article storage |

---

## Build System Changes

### Android

- Modify `android/app/src/main/AndroidManifest.xml` — add to existing `<activity android:name=".MainActivity">`:
  ```xml
  <intent-filter>
    <action android:name="android.intent.action.SEND" />
    <category android:name="android.intent.category.DEFAULT" />
    <data android:mimeType="text/plain" />
    <data android:mimeType="text/*" />
  </intent-filter>
  ```
- No new permissions required.
- No NDK changes (v7 NDK pinning stands).

### iOS

- Add new target: **SpeedyBoyShareExtension** (Share Extension template).
- Both host app and extension need **App Groups** capability with shared group ID `group.app.speedyboy.shared`.
- Host app `Info.plist`: add `CFBundleURLTypes` for scheme `speedyboy`.
- Extension `Info.plist`: `NSExtensionAttributes.NSExtensionActivationRule` set to accept `NSExtensionActivationSupportsText` and `NSExtensionActivationSupportsWebURLWithMaxCount = 1`.
- Extension entitlements: App Groups only — no other permissions.
- Bitcode setting matches v7 (disabled).

### Codemagic Workflow Additions

```yaml
scripts:
  - name: Verify share extension target builds
    script: |
      # iOS workflow only
      xcodebuild -project ios/Runner.xcodeproj \
                 -target SpeedyBoyShareExtension \
                 -configuration Release \
                 -sdk iphonesimulator \
                 build
```

---

## Privacy & Telemetry Notes

This patch reinforces the v7 P19 posture for share intents specifically:

1. Payload contents (text, URL, subject) MUST NOT be logged anywhere — local logs, crash reports, analytics, debug builds included.
2. Source app ID (bundle identifier of sharing app) MAY be logged as metadata — not personally identifying.
3. URL hashes (SHA-256 truncated) MAY appear in cache filenames and logs — the hash is not reversible.
4. Crash reporters (if any are added in future versions) MUST scrub `SharedPayload`, `SharedUrlEntry`, and `ClipboardDocument` instances from any captured stack frames.
5. v7's no-prefetch rule (Rule 37) extends to URL fetches: shared URLs are fetched only on user confirmation or trusted-domain auto-confirm — never on receipt.

---

## Migration Notes (from v7 → v8)

1. AppConfig JSON schema gains 3 new fields. Reading older config files: missing keys → defaults. No migration code required.
2. v7 assistant continues to work on shared URL articles unchanged — the assistant operates on the current sentence (Rule 40), which is source-agnostic.
3. v6 Instapaper integration is untouched. Shared URLs do NOT flow into the Instapaper queue. They are a parallel content source with their own cache and library section.
4. v4 clipboard reading is untouched. Shared text payloads are functionally clipboard documents but enter via a different code path; do not attempt to merge `ClipboardService` and `ShareIntentService`.
