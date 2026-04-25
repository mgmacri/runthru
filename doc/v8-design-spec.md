# Speedy Boy v8.0 — Universal Share Receiver Design Specification

**Product**: Speed-reading app with 3D neumorphic viewport — adding system-level share intent receiving
**Spec Version**: 8.0.0
**Date**: 2026-04-25
**Supersedes**: v7-design-spec.md (on-device assistant release)
**Platform**: Flutter (Dart) — Android, iOS (primary); Windows, macOS, Linux, Web (degraded/no-op)
**Primary Test Device**: Android emulator (Pixel-class, 412×892 @2.6x) + iOS simulator (iPhone 15 Pro)

This document is a **v8 additive specification**. It incorporates all v3–v7 content by reference and specifies all new components, modified components, and integration points for receiving text and URLs from the system share sheet.

This feature was originally noted in the v4 design spec under **Priority 7: Read from Clipboard** as a deferred future item ("Share sheet (future): Receive text from other apps via Android share intent"). v8 promotes it to a first-class feature.

---

## Change Log

| Version | Date | Summary |
|---|---|---|
| 8.0.0 | 2026-04-25 | Universal share receiver: accept text + URL share intents from any app on Android/iOS, route into the existing reading engine |

### v8 Change Summary

| Change | Type | Priority | Complexity | Source |
|---|---|---|---|---|
| Native share intent registration (Android manifest + iOS share extension) | New component | High | M | Platform requirement |
| ShareIntentService (Dart receiver) | New component | High | M | Foundation |
| SharedPayload model | New component | High | XS | Foundation |
| URL → article text resolution | New component | High | M | Reuses v6 InstaparserService |
| ShareIntentRouter (cold-start vs warm-start dispatch) | New component | High | M | Lifecycle requirement |
| Share preview confirmation sheet | New component | Medium | S | UX safety |
| Library "Recently Shared" section | Modified component | Medium | S | DP4 carryover |
| AppConfig — share preferences | Modified component | Low | XS | Foundation |
| ShareReceiveScreen (cold-start landing) | New component | Medium | S | Lifecycle requirement |
| Permission rationale (Android only) | New component | Low | XS | Platform requirement |
| Telemetry-free share logging | Modified behavior | Low | XS | Privacy carryover from v7 |

---

## Design Philosophy

v8 closes the last "how do I get text into this app" gap. v4 added clipboard. v6 added Instapaper. v8 adds **everything else**: any app on the user's phone that exposes a share button (Twitter/X, Reddit, browsers, Gmail, Slack, Notes, RSS readers, Pocket, Kindle highlights, even WhatsApp messages) can send text or a URL directly into Speedy Boy with a single tap.

The friction this removes is significant: the current clipboard flow is **copy → switch app → tap paste**. Universal share is **share → done** (one tap, app launches into reading).

The feature is platform-asymmetric by necessity. Android share intents are a manifest declaration. iOS requires a separate Share Extension target with its own bundle ID, entitlements, and bridging back to the host app via App Groups. The Dart layer abstracts both behind a single `ShareIntentService` interface, but the spec calls out the platform split explicitly so the implementation does not under-budget the iOS work.

The feature is also content-asymmetric: text shares are easy (treat as a long clipboard payload), URL shares are hard (must fetch + extract article text, same problem v6 solved for Instapaper). The good news is v6 already built `InstaparserService` and `HtmlTextExtractor` for exactly this — v8 reuses both rather than duplicating extraction logic.

---

## Design Principles

This version uses lightweight rationale (not evidence-graded) since the feature is platform integration plumbing rather than cognitive/UX research.

### DP1: One Tap from Anywhere

**Statement**: A user reading anything on their phone should be able to send it to Speedy Boy in one share-sheet tap and land in the reading viewport with no further confirmation steps in the happy path. Confirmation sheets only appear when content is ambiguous (mixed text + URL, very short text, multiple URLs).

**Rationale**: The whole point of the feature is to remove friction from the clipboard flow. If the user has to confirm twice, we have made things worse, not better.

### DP2: Reuse the v6 Extraction Pipeline

**Statement**: URL shares go through the same `InstaparserService` → `HtmlTextExtractor` → `Sentence[]` pipeline that Instapaper articles use. No new HTML extraction code. No new tokenizer.

**Rationale**: We already paid the implementation and credit-budget cost for this in v6. Duplicating it would waste credits, double the bug surface, and produce inconsistent reading behavior across content sources.

### DP3: Cold-Start Tolerant

**Statement**: The share intent must work when the app is **not running**, **suspended**, and **already in the foreground**. Each lifecycle state has a different dispatch path, all of which converge on the same `ShareIntentRouter.handle(payload)` entry point.

**Rationale**: Sharing typically happens from a cold-start state (user is in another app). If cold-start drops or delays the payload, the feature is broken in the most common case.

### DP4: No Silent Network Calls

**Statement**: A shared URL never triggers an automatic network fetch on receipt. Fetching happens **after** the user confirms (or after a 1.5s display-then-auto-confirm if the URL is from a trusted-domain allowlist of news/article sites). Text shares never touch the network.

**Rationale**: A malicious or compromised app could spam share intents to drain data or trigger trackable fetches. Confirmation gates the network. Carries v7's silent-by-default posture (P21).

### DP5: Fail Visibly, Recover Gracefully

**Statement**: If a share payload fails to parse, fetch, or extract, the app shows a clear error in the share preview sheet with options: "Try again," "Open as plain text," or "Cancel." Never silently drop a share.

**Rationale**: Share intents are user-initiated — silent failure looks like a broken app. The user already committed to the action; we owe them either a result or a clear explanation.

### DP6: Text Shares Are Ephemeral, Like Clipboard

**Statement**: A shared **text** payload is treated identically to a `ClipboardDocument` (Rule 28): not persisted to the library, ephemeral, cleared on app restart. A shared **URL** payload is persisted to a new "Recently Shared" library section (last 20, FIFO eviction) so the user can return to it.

**Rationale**: Pasted text and shared text are functionally the same — short-lived snippets. Shared URLs map to durable web articles, more like Instapaper bookmarks; the Recently Shared section gives them a home without conflating them with the user's actual Instapaper queue.

---

## New Components

### Component: ShareIntentService

---
**Version**: 1
**Design principle**: DP1, DP3

---

#### Purpose

Single Dart-facing entry point for all share intent payloads regardless of platform. Wraps the platform-channel bridge to native code (Android `Intent.ACTION_SEND` / `ACTION_SEND_MULTIPLE`, iOS Share Extension via App Groups + `UIApplication.openURL`).

**When to use**: App startup (drain any cold-start payload), and as a long-lived stream subscriber for warm-start payloads.
**When NOT to use**: Reading the system clipboard (use `ClipboardService` from v4).

#### States

| State | Description | Trigger |
|---|---|---|
| `idle` | No payload pending | Default |
| `coldStartPending` | App launched by share intent, payload not yet drained | App start, before first frame |
| `warmReceived` | App already running, payload arrived via stream | Native channel emits while app is foreground or backgrounded |
| `processing` | Payload handed to ShareIntentRouter | After drain |
| `error` | Native bridge or parse failure | Channel exception |

#### Behavior

1. **Cold-start drain**: On `main()`, before `runApp()`, call `ShareIntentService.drainInitialPayload()` once. Returns a `SharedPayload?` (null if app was launched normally). Drained payloads are passed to `ShareIntentRouter` after the first frame renders.
2. **Warm-start stream**: Exposes `Stream<SharedPayload> get incomingPayloads`. Subscribed by the root widget; pushes payloads to `ShareIntentRouter` immediately.
3. **Dedup**: A payload received via cold-start MUST NOT also fire via the warm stream. The native bridge marks the cold-start payload consumed before the stream begins emitting.
4. **Platform channel name**: `app.speedyboy/share_intent` (single channel, two methods: `drainInitial`, `subscribe`).
5. **Web/desktop**: All methods are no-ops returning empty/null. No platform errors.

#### Methods

```dart
Future<SharedPayload?> drainInitialPayload();
Stream<SharedPayload> get incomingPayloads;
Future<void> dispose();
```

#### Do / Don't

| Do | Don't | Why |
|---|---|---|
| Drain cold-start payload before `runApp()` | Wait until after first frame to drain | Payload may be lost if `MainActivity` is recreated |
| Mark cold-start payloads as consumed in native | Allow same payload to fire twice | Causes double-navigation, duplicate library entries |
| Return null from drain on normal launch | Throw or return empty payload | `null` is the unambiguous "no share" signal |
| Treat web/desktop as no-op | Throw `UnimplementedError` on unsupported platforms | App must not crash on unsupported platforms |

---

### Component: SharedPayload

---
**Version**: 1

---

#### Purpose

Data model representing a single share intent payload. Always has either text, a URL, or both (rare but possible — e.g., a tweet share includes the tweet text and a URL).

#### Fields

| Field | Type | Source | Notes |
|---|---|---|---|
| `text` | `String?` | Native bridge | Plain text content; null if URL-only share |
| `url` | `String?` | Native bridge | Single URL extracted from payload; null if text-only |
| `subject` | `String?` | Native bridge | Optional title (Android `Intent.EXTRA_SUBJECT`, iOS `NSExtensionItem.attributedTitle`) |
| `sourceAppId` | `String?` | Native bridge | Bundle ID / package name of sharing app, when available |
| `receivedAt` | `DateTime` | Local | Set in Dart on receipt |
| `kind` | `SharedPayloadKind` | Computed | `text`, `url`, `mixed` (both present) |

#### Methods

```dart
factory SharedPayload.fromNative(Map<String, dynamic> raw);
Map<String, dynamic> toJson();

bool get hasText => text != null && text!.trim().length >= 10;
bool get hasUrl => url != null && Uri.tryParse(url!) != null;
SharedPayloadKind get kind { ... }
String get displayTitle => subject ?? url ?? (text?.substring(0, math.min(40, text!.length)) ?? '(empty)');
```

#### Enum

```dart
enum SharedPayloadKind { text, url, mixed, empty }
```

`empty` is used when the payload survived parse but has neither usable text nor a valid URL. `ShareIntentRouter` handles it by showing the error sheet.

---

### Component: ShareIntentRouter

---
**Version**: 1
**Design principle**: DP1, DP3, DP5

---

#### Purpose

Decides what to do with a `SharedPayload` and dispatches accordingly: open the reading viewport directly, show a confirmation sheet, fetch a URL, or surface an error.

**When to use**: Receives every `SharedPayload` from `ShareIntentService` (both cold-start and warm-start paths).
**When NOT to use**: Direct user actions in-app (clipboard button, library tap) — those have their own routes.

#### Decision Table

| Payload | App state | Action |
|---|---|---|
| `text` (≥10 chars, no URL) | Any | Build `ClipboardDocument`, push `/read-clipboard` |
| `url` only, trusted domain | Any | Show 1.5s preview banner → auto-fetch → push `/read-shared-url` |
| `url` only, untrusted domain | Any | Push `/share-preview` sheet, user confirms → fetch → push `/read-shared-url` |
| `mixed` (text + url) | Any | Push `/share-preview` sheet, user picks "Read text" or "Read article" |
| `text` (<10 chars) | Any | Push `/share-preview` sheet with error: "Shared text is too short to read" |
| `empty` | Any | Push `/share-preview` sheet with error: "No readable content found" |

#### Behavior

1. Cold-start dispatch waits for the first frame (`WidgetsBinding.instance.addPostFrameCallback`) before navigating, so the navigator is mounted.
2. Warm-start dispatch can navigate immediately (navigator already mounted).
3. If the user is currently in `ParallaxReadingScreen`, the router shows a "New share received — Read now?" snackbar with [Read][Save for later][Dismiss] rather than interrupting the active reading session.
4. Trusted-domain allowlist lives in `ShareIntentRouter._trustedDomains` — initially: `medium.com`, `substack.com`, `*.substack.com`, `nytimes.com`, `theguardian.com`, `arstechnica.com`, `wired.com`, `theatlantic.com`, `newyorker.com`, `washingtonpost.com`. Editable via `AppConfig.trustedShareDomains`.
5. Every dispatch logs metadata only (per Rule 36/v7 carryover): payload kind, source app ID, fetch latency, success/failure. **Never** the text content or URL itself.

#### Do / Don't

| Do | Don't | Why |
|---|---|---|
| Wait for first frame on cold-start before navigating | Navigate before `runApp()` completes | No navigator mounted; crash |
| Show snackbar (not modal) when reading is active | Hard-interrupt with full-screen takeover | Respects active reading session |
| Use the v6 `InstaparserService` for URL fetching | Build a new HTTP fetch path | DP2 |
| Strip URL query params from logs | Log full URLs | Privacy; URLs often contain tokens |

---

### Component: ShareReceiveScreen

---
**Version**: 1
**Design principle**: DP3 (Cold-Start Tolerant)

---

#### Purpose

Brief landing screen shown for the ~50–200ms between cold-start app launch and first navigation to the actual destination. Prevents the user from seeing the library flicker and disappear.

**When to use**: Cold-start share intent path only.
**When NOT to use**: Warm-start (no flicker problem).

#### Anatomy

```
┌─────────────────────────────────┐
│                                 │
│         [Speedy Boy logo]       │
│                                 │
│      Loading shared content…    │
│                                 │
│           [progress ring]       │
│                                 │
└─────────────────────────────────┘
```

- Centered logo, single-line caption, neumorphic progress ring.
- Background: `shellBase`. Caption: `shellTextSecondary`, `shellCaption` typography.
- Auto-replaced by router decision within 200ms in the happy path. If still on screen at 5s, replace with error sheet (network or parse stuck).

#### Tokens Consumed

| Token | Usage |
|---|---|
| `shellBase` | Background |
| `shellTextSecondary` | Caption text |
| `shellAccent` | Progress ring stroke |

---

### Component: SharePreviewSheet

---
**Version**: 1
**Design principle**: DP1 (one tap), DP5 (visible failure)

---

#### Purpose

Bottom sheet shown for ambiguous, untrusted, or failed share payloads. Gives the user enough information to decide what to do without forcing them to leave the share-sheet flow.

**When to use**: Mixed text+URL payloads, untrusted-domain URLs, error cases.
**When NOT to use**: Trusted-domain URL shares (auto-confirm with banner instead).

#### Anatomy — Mixed payload

```
┌─────────────────────────────────────┐
│ Shared from [App name]              │
│                                     │
│ [URL preview card]                  │
│   example.com                       │
│   "Article title (if known)"        │
│                                     │
│ [Text preview card]                 │
│   "First 120 characters of shared   │
│    text..."                         │
│                                     │
│ [Read article]  [Read text]         │
│           [Cancel]                  │
└─────────────────────────────────────┘
```

#### Anatomy — Untrusted URL

```
┌─────────────────────────────────────┐
│ Shared from [App name]              │
│                                     │
│ example.com                         │
│ Speedy Boy will fetch this article  │
│ and read it offline.                │
│                                     │
│   [Read]  [Always trust example.com]│
│           [Cancel]                  │
└─────────────────────────────────────┘
```

#### Anatomy — Error

```
┌─────────────────────────────────────┐
│ ⚠ Couldn't load shared content      │
│                                     │
│ Network error: timed out            │
│                                     │
│   [Try again]  [Read as plain text] │
│           [Cancel]                  │
└─────────────────────────────────────┘
```

#### Behavioral Rules

1. Sheet is dismissible by swipe-down (matches `assistantSheetDismissVelocity` from v7 = 300 px/s).
2. "Always trust" button adds the domain to `AppConfig.trustedShareDomains` and proceeds with fetch in the same step.
3. "Read as plain text" on error path packages the URL string itself as a `ClipboardDocument` (lets the user at least see what was shared).
4. Cancel → dismiss sheet → no navigation. The cold-start `ShareReceiveScreen` is replaced by the library if cancel happens during cold-start.

#### Do / Don't

| Do | Don't | Why |
|---|---|---|
| Show source app ID when known | Hide payload provenance | User trust signal |
| Default focus to the safer option | Default to "Read article" with no confirmation on untrusted URL | DP4 |
| Allow swipe-down dismiss | Require button-only dismiss | UX consistency with v7 sheet |
| Show fetch error message verbatim | Replace with generic "Something went wrong" | DP5 — visible failure |

---

### Component: SharedUrlCache

---
**Version**: 1
**Design principle**: DP2, DP6

---

#### Purpose

Local persistence for shared URLs that the user fetched and read. Powers the library's "Recently Shared" section. Mirrors `InstapaperCache` in shape but lives in a separate directory.

**When to use**: Storing/retrieving shared URL payloads and their extracted text.
**When NOT to use**: Shared text payloads (those are ephemeral per DP6).

#### Behavior

1. Storage: `<appSupport>/shared_url_cache/index.json` for the metadata list, `<appSupport>/shared_url_cache/articles/<urlHash>.json` for extracted text per URL.
2. URL hash: `sha256(url)` truncated to 16 hex chars.
3. List capped at 20 entries, FIFO eviction (oldest read replaces). Cap configurable via `AppConfig.recentlySharedCap`.
4. `add(SharedUrlEntry entry)` writes both index and article file, evicts if over cap.
5. `list()` returns entries newest-first.
6. `clearAll()` deletes the entire `shared_url_cache/` directory — exposed in Settings → "Clear shared history".
7. All file I/O runs in `Isolate.run()` (Rule 11).

#### SharedUrlEntry Model

```dart
class SharedUrlEntry {
  final String url;
  final String urlHash;
  final String? title;
  final String? domain;
  final DateTime sharedAt;
  final int? wordCount;
  final double progress; // 0.0–1.0, updated as user reads
}
```

---

### Component: Library — Recently Shared Section

---
**Version**: 1
**Design principle**: DP4 (carry over from v6: source-driven sections)

---

#### Purpose

New collapsible library section showing URLs the user has shared into the app. Sits between the v6 Instapaper section and the v5 Local Files section.

#### Anatomy

```
LIBRARY
├── INSTAPAPER       (v6, if connected)
│   └── [article cards]
│
├── RECENTLY SHARED  (v8, if non-empty)         ← NEW
│   ├── [shared URL card]
│   ├── [shared URL card]
│   └── …
│
└── LOCAL FILES
    └── [PDF cards]
```

Each shared URL card uses the v6 `ArticleCard` widget unchanged (URL + title + word count + progress bar). The only difference is the section header label and a long-press menu with [Open], [Remove from history], [Clear all shared].

#### Behavioral Rules

1. Section only renders when the cache has ≥1 entry.
2. Tap → `/read-shared-url?hash=<urlHash>` (cached → render immediately).
3. Long-press → context menu.
4. Section is independent of Instapaper connection state — works even with Instapaper disconnected.

---

## Modified Components

### Modified: AppRouter — Share Routes

**Change type**: New routes

#### Specification

```dart
GoRoute(
  path: '/share-receive',
  pageBuilder: (context, state) => MaterialPage(child: const ShareReceiveScreen()),
),

GoRoute(
  path: '/share-preview',
  pageBuilder: (context, state) {
    final payload = state.extra as SharedPayload;
    return ModalPage(child: SharePreviewSheet(payload: payload));
  },
),

GoRoute(
  path: '/read-shared-url',
  pageBuilder: (context, state) {
    final hash = state.uri.queryParameters['hash']!;
    return wallFoldTransitionPage(
      key: state.pageKey,
      child: ParallaxReadingScreen(
        filePath: 'shared-url://$hash',
        sharedUrlHash: hash, // NEW parameter
      ),
    );
  },
),
```

`/read-shared-url` reuses `wallFoldTransitionPage` for visual consistency with PDF/Instapaper reading routes.

---

### Modified: ParallaxReadingScreen — Shared URL Source

**Change type**: New content source

#### Specification

```dart
class ParallaxReadingScreen extends ConsumerStatefulWidget {
  const ParallaxReadingScreen({
    super.key,
    required this.filePath,
    this.clipboardDocument,
    this.instapaperBookmark,
    this.sharedUrlHash,         // NEW — v8
  });

  final String filePath;
  final ClipboardDocument? clipboardDocument;
  final InstapaperBookmark? instapaperBookmark;
  final String? sharedUrlHash;  // NEW
}
```

**Initialization flow for shared URLs:**
1. `SharedUrlCache.get(sharedUrlHash)` → cached entry.
2. If `cachedText` present → tokenize directly via `HtmlTextExtractor.htmlToWords()` (already plain text from prior fetch — pass-through).
3. If not cached: fetch via v6 `InstaparserService.extractArticle(entry.url)` → cache result via `SharedUrlCache.update()`.
4. Seek to `entry.progress * wordCount`.
5. Same RSVP/gesture/ContextReveal/WPM/sheet behavior as PDFs.

**Progress tracking:**
- On pause: update `SharedUrlEntry.progress` via `SharedUrlCache.updateProgress()`. Local-only (no remote sync).

#### Behavioral Rules

1. All v3–v7 features work identically.
2. `_isSharedUrl` guard mirrors `_isInstapaper` and `_isClipboard` patterns.
3. v7 assistant works on shared URL articles identically to PDFs.
4. If URL fetch fails on first read, navigate back to `/share-preview` with the error.

---

### Modified: AppConfig — Share Fields

**Change type**: New fields

#### Specification

```dart
final bool universalShareEnabled;            // default: true
final List<String> trustedShareDomains;       // default: [seed list above]
final int recentlySharedCap;                  // default: 20
```

**New ConfigNotifier methods:**

```dart
Future<void> setUniversalShareEnabled(bool enabled);
Future<void> addTrustedShareDomain(String domain);
Future<void> removeTrustedShareDomain(String domain);
Future<void> setRecentlySharedCap(int cap);   // clamp [5, 100]
```

All follow the existing `_synchronized(() async { ... })` pattern. JSON round-trip backward compatible (missing keys → defaults).

---

### Modified: Settings Screen — Sharing Section

**Change type**: New section

#### Specification

```
SHARING
┌─────────────────────────────────────┐
│ ☑ Accept shares from other apps     │
│                                     │
│ Trusted domains (auto-fetch)        │
│ • medium.com               [Remove] │
│ • substack.com             [Remove] │
│ • …                                 │
│ [Add domain]                        │
│                                     │
│ Recently shared history             │
│ Keep last [20 ▼] articles           │
│ [Clear shared history]              │
└─────────────────────────────────────┘
```

- Toggle disables share intent registration (Android: handled at runtime by ignoring incoming intents; iOS: extension still installed but app refuses payloads).
- Domain list editable.
- Clear history → deletes `SharedUrlCache` directory and library section.

---

## Platform Implementation Notes

### Android

- `AndroidManifest.xml` — add `<intent-filter>` to `MainActivity` for `ACTION_SEND` with mime types `text/plain` and `text/*`. Optionally add `ACTION_PROCESS_TEXT` for highlighted-text shares.
- Read intent in `MainActivity.onCreate()` (cold-start) and `onNewIntent()` (warm-start). Push payload across `MethodChannel` `app.speedyboy/share_intent`.
- No additional permissions required — intent receiving is implicit.
- App label in share sheet: "Speedy Boy". Icon: existing launcher icon.

### iOS

- New target: **Share Extension** (`SpeedyBoyShareExtension`). Bundle ID: `<base>.SharedExtension`.
- Extension UI: minimal — accepts text/URL, writes to App Group container `group.app.speedyboy.shared`, then calls `extensionContext.completeRequest()` and opens host app via `extensionContext.open(URL)` with custom scheme `speedyboy://share?id=<uuid>`.
- Host app: register URL scheme `speedyboy`, handle in `AppDelegate.application(_:open:options:)`. Read payload from App Group, push to Dart via channel.
- Entitlements: App Groups capability on both host app and extension.
- Info.plist on extension: `NSExtensionAttributes.NSExtensionActivationRule` accepting text + URL types.

### Web/Desktop

- `ShareIntentService` is a no-op stub. The library section is hidden when no shared URLs exist (which it never will). Settings section is hidden entirely.

---

## New Dependencies

| Package | Purpose | Notes |
|---|---|---|
| `receive_sharing_intent` (or hand-rolled platform channel) | Bridge for share intents | Evaluate — package exists but maintenance status varies. Hand-rolled is ~300 lines per platform but no third-party risk. |
| `crypto` | SHA-256 for URL hashing | Likely already transitive via `http` |

**Already available**: v6's `InstaparserService` (URL fetching), `HtmlTextExtractor` (HTML → words), `http` package.

---

## Integration Test Scenarios

| Test | Description |
|---|---|
| Cold-start text share | App killed → share text from another app → app launches → reading viewport opens with shared text |
| Cold-start URL share (trusted) | App killed → share medium.com URL → 1.5s banner → reading viewport opens with article |
| Cold-start URL share (untrusted) | App killed → share random URL → preview sheet → confirm → reading viewport |
| Warm-start text share | App in foreground → share text → reading viewport replaces current screen |
| Warm-start during reading | App actively reading PDF → share text → snackbar offers [Read now][Save][Dismiss] |
| Mixed payload (text + URL) | Share a tweet (text + URL) → preview sheet → user picks "Read article" → URL fetched |
| Network failure on URL fetch | Share URL with no network → error sheet → "Try again" or "Read as plain text" |
| Add trusted domain via sheet | Untrusted URL → "Always trust" → confirm → domain added to AppConfig → next share from same domain auto-fetches |
| Recently Shared cap eviction | Share 21 distinct URLs → verify oldest is evicted, count stays at 20 |
| Disable share toggle | Disable sharing in Settings → share intent → app receives but rejects payload silently |
| Disconnect Instapaper, share URL | Verify shared URL section works independently of Instapaper connection |
| Share intent during v7 assistant sheet open | Verify assistant sheet dismisses cleanly before share flow proceeds |
| iOS share extension cold-start | Kill app → share from Safari → extension opens host app → payload delivered intact |
| Web/desktop launch | Verify no crash, no share UI elements visible |

---

## Out of Scope (Explicitly Deferred to v9+)

| Feature | Reason |
|---|---|
| Image share intents (OCR) | Significant added complexity; OCR engine selection is its own design exercise |
| File share intents (PDFs) | Possible but overlaps with v3 PDF import; defer to v9 design pass |
| Multi-URL shares (e.g., 5 URLs at once) | Edge case; v8 takes the first valid URL and ignores the rest with a notice |
| Share *out* of Speedy Boy (sending text to other apps) | Different feature category — "share my reading" |
| iOS Action Extension (vs Share Extension) | Action Extensions show in different UI surface; Share Extension covers 95% of cases |
| Android quick-tile / shortcut for "read clipboard" | Adjacent feature, separate spec |
| Cross-device share (handoff) | Apple-only, niche, large surface area |
