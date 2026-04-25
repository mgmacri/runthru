# Speedy Boy v8.0 — Task Backlog

**Generated**: 2026-04-25
**Spec version**: 8.0.0 (Universal Share Receiver)
**Codebase scanned**: c:\Users\Matthew\speedy-boyv3 (assumed v7-complete baseline)

## Scan Summary

- **Implemented**: 0 / 11 v8 priorities
- **Partial**: 0 / 11 v8 priorities
- **Not started**: 11 / 11 v8 priorities
- **Total tasks generated**: 23

## Blockers & Ambiguities

1. **iOS Share Extension requires Apple Developer Program membership.** A Share Extension is a separate target with its own App ID, provisioning profile, and entitlements. Cannot be built/tested on simulator alone for distribution — TestFlight or device install needed. Mock-test the Dart layer (TASK-410) without the extension.

2. **`receive_sharing_intent` package vs hand-rolled platform channel.** The package exists but its maintenance cadence has been irregular historically. TASK-401 should evaluate: package (~30 min integration) vs hand-rolled channel (~3–4 hr but zero third-party risk). Decision should be locked before TASK-403 begins.

3. **Trusted-domain wildcard semantics.** Spec says `*.substack.com` matches any subdomain. Implementation must define: does `*.substack.com` also match the root `substack.com`? Recommendation: yes (treat `*.X` as "X plus any subdomain"). Lock decision in TASK-402.

4. **Cold-start payload provider initialization order.** Riverpod containers and `WidgetsFlutterBinding.ensureInitialized()` must run before `ShareIntentService.drainInitialPayload()`, but `runApp()` must come after the drain. TASK-404 specifies the exact `main()` ordering — review carefully before implementing.

5. **iOS App Group ID consistency.** Host app and extension must agree on `group.app.speedyboy.shared`. Mismatch is silent and breaks payload transfer. TASK-407 includes a verification step.

6. **Snackbar during active reading vs v7 assistant sheet.** If both are visible, the snackbar must not collide with the AssistantSheet. TASK-413 must verify visual stacking and dismiss interaction order.

7. **`crypto` package availability.** Likely already transitive via `http`/`oauth1`, but TASK-401 should confirm — if not transitive, add explicit dependency.

8. **Web/desktop graceful degradation.** All v8 UI surfaces must be hidden or no-op on web/desktop. TASK-420 audits this.

---

## Sprint 1: Foundation — Models, Config, Native Bridge

### TASK-400: Add v8 dependencies to pubspec.yaml
- **Priority**: 0 (prerequisite)
- **Files**: `MODIFY: pubspec.yaml`
- **Action**: Decide between `receive_sharing_intent` package and hand-rolled platform channel (per Blocker 2). If package: add to dependencies. Confirm `crypto` is available (transitive or explicit). Run `flutter pub get`.
- **Acceptance criteria**:
  - [ ] Decision documented in TASK comment: package vs hand-rolled
  - [ ] If package: pinned version in pubspec.yaml
  - [ ] `crypto` package usable from Dart (test with `import` + simple SHA-256 call)
  - [ ] `flutter pub get` succeeds
  - [ ] `dart analyze lib/` reports 0 issues (no regression)
- **Principles**: None (infrastructure)
- **Effort**: XS (~15 min)
- **Depends on**: Nothing

### TASK-401: Create SharedPayload model + SharedPayloadKind enum
- **Priority**: 0 (prerequisite)
- **Files**: `CREATE: lib/models/shared_payload.dart`
- **Action**: Implement `SharedPayload` with fields: `text` (String?), `url` (String?), `subject` (String?), `sourceAppId` (String?), `receivedAt` (DateTime), `kind` (computed). Implement `SharedPayloadKind` enum: `text`, `url`, `mixed`, `empty`. Implement `fromNative(Map)`, `toJson()`, `hasText`, `hasUrl`, `kind` getter, `displayTitle` getter.
- **Acceptance criteria**:
  - [ ] All fields declared with correct nullability
  - [ ] `fromNative` handles missing keys gracefully (all nullable)
  - [ ] `kind` returns `text` when text only, `url` when URL only, `mixed` when both, `empty` when neither usable
  - [ ] `hasText` requires `text != null && text.trim().length >= 10`
  - [ ] `hasUrl` requires `Uri.tryParse(url) != null` and `url.startsWith('http')`
  - [ ] `displayTitle` falls back: subject → url → text[:40] → '(empty)'
  - [ ] `dart analyze` reports 0 issues on this file
  - [ ] Unit tests cover all kind permutations
- **Principles**: None (data model)
- **Effort**: S (~25 min)
- **Depends on**: Nothing

### TASK-402: Create SharedUrlEntry model + SharedUrlCache service
- **Priority**: 0 (prerequisite)
- **Files**: `CREATE: lib/models/shared_url_entry.dart`, `CREATE: lib/services/shared_url_cache.dart`
- **Action**: Implement `SharedUrlEntry` (url, urlHash, title, domain, sharedAt, wordCount, progress) with fromJson/toJson. Implement `SharedUrlCache` with: `add(entry)`, `get(hash)`, `list()` (newest-first), `updateProgress(hash, progress)`, `remove(hash)`, `clearAll()`. Storage layout: `<appSupport>/shared_url_cache/index.json` + `<appSupport>/shared_url_cache/articles/<hash>.json`. URL hash via `sha256(url)` truncated to 16 hex chars. FIFO eviction at cap. All file I/O in `Isolate.run()`.
- **Acceptance criteria**:
  - [ ] All entry fields with correct types
  - [ ] `urlHash` deterministic for the same URL
  - [ ] `add` evicts oldest when over cap (test: insert 21, expect 20 with oldest removed)
  - [ ] `list()` returns newest-first
  - [ ] `clearAll()` deletes the entire `shared_url_cache/` directory
  - [ ] All file I/O wrapped in `Isolate.run()` (Rule 11)
  - [ ] Cache survives app restart (round-trip test)
  - [ ] Wildcard domain matching helper: `matchesTrustedDomain('foo.substack.com', '*.substack.com')` → true
  - [ ] Wildcard domain matching helper: `matchesTrustedDomain('substack.com', '*.substack.com')` → true (per Blocker 3 decision)
  - [ ] `dart analyze` reports 0 issues
- **Principles**: DP2, DP6
- **Effort**: M (~1 hr)
- **Depends on**: TASK-400, TASK-401

### TASK-403: AppConfig additions for v8
- **Priority**: 0 (prerequisite)
- **Files**: `MODIFY: lib/store/models.dart`, `MODIFY: lib/store/config.dart`
- **Action**: Add `universalShareEnabled` (bool, default true), `trustedShareDomains` (List<String>, default seed list per copilot patch), `recentlySharedCap` (int, default 20). Add `copyWith` support. Add ConfigNotifier methods: `setUniversalShareEnabled`, `addTrustedShareDomain`, `removeTrustedShareDomain`, `setRecentlySharedCap` (clamp [5, 100]). All follow `_synchronized` pattern. JSON backward-compatible.
- **Acceptance criteria**:
  - [ ] Three new fields in AppConfig with correct defaults
  - [ ] Seed list of 10 trusted domains exactly per copilot patch
  - [ ] `copyWith` supports all three new fields
  - [ ] `toJson`/`fromJson` round-trips correctly
  - [ ] Missing keys in JSON → defaults (backward compatible)
  - [ ] `setRecentlySharedCap(3)` clamps to 5; `setRecentlySharedCap(200)` clamps to 100
  - [ ] `addTrustedShareDomain` deduplicates
  - [ ] `removeTrustedShareDomain` no-ops on missing entry
  - [ ] All four setters follow `_synchronized` pattern
  - [ ] `dart analyze lib/` reports 0 issues
- **Principles**: None (foundation)
- **Effort**: S (~25 min)
- **Depends on**: Nothing

---

## Sprint 2: Native Bridge & Service Layer

### TASK-404: Implement Android MainActivity share intent handling
- **Priority**: 1
- **Files**: `MODIFY: android/app/src/main/AndroidManifest.xml`, `MODIFY: android/app/src/main/kotlin/.../MainActivity.kt`
- **Action**: Add `<intent-filter>` for `ACTION_SEND` with mime types `text/plain` and `text/*` to MainActivity. In MainActivity.kt: override `onCreate` to capture `intent.getStringExtra(Intent.EXTRA_TEXT)` and `intent.getStringExtra(Intent.EXTRA_SUBJECT)`. Override `onNewIntent` for warm-start. Set up MethodChannel `app.speedyboy/share_intent` with two methods: `drainInitial` (returns the cold-start payload as Map<String, Any?>?, then nulls it) and `subscribe` (no-op for setup; warm-starts pushed via `EventChannel`). Use `EventChannel` `app.speedyboy/share_intent/stream` for warm-start events.
- **Acceptance criteria**:
  - [ ] Intent filter declared correctly
  - [ ] App appears in system share sheet for text shares
  - [ ] `drainInitial` returns Map with text/url/subject/sourceAppId, then returns null on second call
  - [ ] Warm-start `onNewIntent` pushes to event channel
  - [ ] Cold-start payload NOT also fired via warm stream (Rule 44)
  - [ ] `intent.`package`` used for source app ID where available
  - [ ] No crash when share has no EXTRA_TEXT
- **Principles**: DP3
- **Effort**: M (~1.5 hr)
- **Depends on**: TASK-400

### TASK-405: Implement iOS Share Extension target
- **Priority**: 1
- **Files**: `CREATE: ios/SpeedyBoyShareExtension/` (new Xcode target), `CREATE: ios/SpeedyBoyShareExtension/ShareViewController.swift`, `CREATE: ios/SpeedyBoyShareExtension/Info.plist`, `CREATE: ios/SpeedyBoyShareExtension/SpeedyBoyShareExtension.entitlements`
- **Action**: Add new Share Extension target in Xcode. Bundle ID `<base>.SpeedyBoyShareExtension`. Configure App Group `group.app.speedyboy.shared` on both host and extension. ShareViewController: read `extensionContext.inputItems[0].attachments`, extract text/URL via `NSItemProvider.loadItem(forTypeIdentifier:)`, write payload as JSON to App Group container at `shared_payload.json`, generate UUID, call `extensionContext.completeRequest(returningItems: nil)`, then `extensionContext.open(URL(string: "speedyboy://share?id=\(uuid)")!)`.
- **Acceptance criteria**:
  - [ ] Share Extension target builds for simulator and device
  - [ ] App Group entitlement on both targets with same group ID
  - [ ] Extension appears in iOS share sheet for text and URL shares
  - [ ] Payload JSON written to App Group container (verify via temporary file inspection)
  - [ ] Custom URL scheme `speedyboy` opens host app
  - [ ] Info.plist `NSExtensionAttributes.NSExtensionActivationRule` accepts text + URL types
  - [ ] No crash when payload has no usable content
- **Principles**: DP3
- **Effort**: L (~3 hr — first iOS extension is always slower)
- **Depends on**: TASK-400

### TASK-406: Implement iOS host app URL scheme + payload reader
- **Priority**: 1
- **Files**: `MODIFY: ios/Runner/AppDelegate.swift`, `MODIFY: ios/Runner/Info.plist`
- **Action**: Add `CFBundleURLTypes` entry for scheme `speedyboy` to Info.plist. In AppDelegate: implement `application(_:open:options:)` to parse `speedyboy://share?id=<uuid>`, read `shared_payload.json` from App Group container, push to MethodChannel `app.speedyboy/share_intent` (matching the Android channel). Wire cold-start: in `application(_:didFinishLaunchingWithOptions:)`, check `launchOptions[.url]` and stash payload for `drainInitial`.
- **Acceptance criteria**:
  - [ ] URL scheme registered correctly
  - [ ] Cold-start: kill app → share text from Safari → app launches → `drainInitial` returns payload
  - [ ] Warm-start: app open → share from Safari → payload arrives via event channel within 500ms
  - [ ] Payload file deleted after successful read (no replay on next launch)
  - [ ] Same MethodChannel name as Android (`app.speedyboy/share_intent`)
  - [ ] Cold-start payload NOT also fired via warm stream
- **Principles**: DP3
- **Effort**: M (~1.5 hr)
- **Depends on**: TASK-405

### TASK-407: Verify App Group ID consistency + end-to-end iOS share
- **Priority**: 1
- **Files**: All iOS files from TASK-405, TASK-406
- **Action**: Audit all iOS files for the App Group ID. Add a build-time assertion (or README check) that host and extension match. Run end-to-end: kill app → share text from Notes → verify payload arrives in Dart with correct text and source app ID.
- **Acceptance criteria**:
  - [ ] App Group ID identical in: host entitlements, extension entitlements, ShareViewController.swift container access, AppDelegate.swift container access
  - [ ] End-to-end manual test passes (logged in TASK comment)
  - [ ] No App Group access errors in console
- **Principles**: DP3
- **Effort**: S (~30 min)
- **Depends on**: TASK-405, TASK-406

### TASK-408: Create ShareIntentService (Dart facade)
- **Priority**: 2
- **Files**: `CREATE: lib/services/share_intent_service.dart`
- **Action**: Wrap the platform channel. `Future<SharedPayload?> drainInitialPayload()` calls `MethodChannel.invokeMethod('drainInitial')` and parses via `SharedPayload.fromNative`. `Stream<SharedPayload> get incomingPayloads` wraps the `EventChannel`. `Future<void> dispose()` cancels stream subscription. Web/desktop: all methods are no-ops (drain returns null, stream emits nothing).
- **Acceptance criteria**:
  - [ ] `drainInitialPayload` returns null on normal launch
  - [ ] `drainInitialPayload` returns SharedPayload on share-launched cold-start
  - [ ] `incomingPayloads` is a broadcast stream (multiple subscribers OK)
  - [ ] Returns no-op on web (`kIsWeb` check) — no platform exception
  - [ ] Returns no-op on desktop (Linux/macOS/Windows) — no platform exception
  - [ ] No payload contents logged anywhere (Rule 46) — only metadata
  - [ ] `dart analyze` reports 0 issues
  - [ ] Unit tests with mocked MethodChannel
- **Principles**: DP1, DP3
- **Effort**: S (~45 min)
- **Depends on**: TASK-401, TASK-404, TASK-406

### TASK-409: Wire ShareIntentService into main()
- **Priority**: 2
- **Files**: `MODIFY: lib/main.dart`
- **Action**: In `main()`: `WidgetsFlutterBinding.ensureInitialized()` → create ProviderContainer → `await ShareIntentService.drainInitialPayload()` → store in `initialSharedPayloadProvider` (top-level Riverpod provider) → `runApp()`. Subscribe to `incomingPayloads` stream from a root widget after first frame.
- **Acceptance criteria**:
  - [ ] `drainInitialPayload` awaited BEFORE `runApp()` (Rule 43)
  - [ ] Cold-start payload reaches `initialSharedPayloadProvider`
  - [ ] Warm-start subscription set up in `addPostFrameCallback`
  - [ ] Normal launch: provider is null, no errors
  - [ ] App launch time regression < 50ms (drain is fast)
  - [ ] `dart analyze` reports 0 issues
- **Principles**: DP3
- **Effort**: S (~30 min)
- **Depends on**: TASK-408

---

## Sprint 3: Router, UI, Reading Integration

### TASK-410: Create ShareIntentRouter
- **Priority**: 3
- **Files**: `CREATE: lib/services/share_intent_router.dart`
- **Action**: Implement decision table from spec. `Future<void> handle(SharedPayload payload, {required BuildContext? context})`. Logic: if active reading screen → snackbar; else if `kind == text` → `/read-clipboard` with built ClipboardDocument; else if `kind == url` and trusted domain → `/share-receive` 1.5s banner → fetch → `/read-shared-url`; else if `kind == url` and untrusted → `/share-preview`; else if `kind == mixed` → `/share-preview`; else (`empty` or short text) → `/share-preview` with error. Use `GoRouter.of(context)` for navigation. Trusted-domain check via `AppConfig.trustedShareDomains` with wildcard support per TASK-402.
- **Acceptance criteria**:
  - [ ] Decision table fully covered: text, trusted URL, untrusted URL, mixed, empty, short text
  - [ ] Active reading detection: snackbar shown with 3 actions
  - [ ] Wildcard trusted domains match correctly
  - [ ] URL fetch via v6 `InstaparserService` (Rule 48 — no parallel pipeline)
  - [ ] Logs metadata only — no text, no URL (Rule 46)
  - [ ] `dart analyze` reports 0 issues
  - [ ] Unit tests for every decision-table row
- **Principles**: DP1, DP2, DP4, DP5, Rule 48, Rule 49
- **Effort**: M (~1.5 hr)
- **Depends on**: TASK-402, TASK-403, TASK-408

### TASK-411: Create ShareReceiveScreen
- **Priority**: 3
- **Files**: `CREATE: lib/screens/share_receive_screen.dart`
- **Action**: Stateless screen with centered logo, "Loading shared content…" caption, neumorphic progress ring. Background `shellBase`. After 5s with no router decision, replace itself with `SharePreviewSheet` showing a timeout error. Replaced by router decision otherwise.
- **Acceptance criteria**:
  - [ ] Renders logo + caption + progress ring
  - [ ] Uses correct design tokens (`shellBase`, `shellTextSecondary`, `shellAccent`)
  - [ ] 5-second timeout → error sheet (`shareReceiveScreenTimeoutMs`)
  - [ ] Accessible: progress ring has semantic label "Loading shared content"
  - [ ] No raw Material widgets (Rule 15)
  - [ ] `dart analyze` reports 0 issues
- **Principles**: DP3
- **Effort**: S (~30 min)
- **Depends on**: TASK-403

### TASK-412: Create SharePreviewSheet
- **Priority**: 3
- **Files**: `CREATE: lib/widgets/share_preview_sheet.dart`
- **Action**: Modal bottom sheet rendering one of three layouts: mixed payload (URL + text + 2 read buttons), untrusted URL (URL + Read + Always trust), error (icon + message + Try again / Read as plain text). Source app ID shown when known. Swipe-down dismiss at velocity `sharePreviewDismissVelocity`. "Always trust" calls `ConfigNotifier.addTrustedShareDomain(domain)` then proceeds with fetch in same step. "Read as plain text" packages URL string as `ClipboardDocument`. Sheet enter/exit animations match v7 (`shareSheetEnterMs`/`shareSheetExitMs`).
- **Acceptance criteria**:
  - [ ] All three layouts render correctly
  - [ ] Source app ID shown when available, hidden when not
  - [ ] Swipe-down dismiss works at correct velocity
  - [ ] "Always trust" adds domain and continues fetch
  - [ ] "Read as plain text" creates ClipboardDocument with URL string
  - [ ] Sheet uses correct enter/exit timings
  - [ ] No payload contents logged (Rule 46)
  - [ ] Accessible: each button has semantic label
  - [ ] `dart analyze` reports 0 issues
- **Principles**: DP1, DP4, DP5
- **Effort**: M (~1.5 hr)
- **Depends on**: TASK-401, TASK-403

### TASK-413: Implement active-reading snackbar handling
- **Priority**: 3
- **Files**: `MODIFY: lib/screens/parallax_reading_screen.dart`, possibly `MODIFY: lib/services/share_intent_router.dart`
- **Action**: When `ShareIntentRouter.handle` is called and current route is `/read*`, show snackbar (custom neumorphic, NOT Material `SnackBar` per Rule 15) with [Read now][Save for later][Dismiss]. "Read now" → navigate to share destination. "Save for later" → if URL, add to `SharedUrlCache` without fetching; if text, no-op (text is ephemeral). "Dismiss" → close snackbar. Auto-dismiss at `shareSnackbarDurationMs` (6s). Verify it does not collide visually with v7 AssistantSheet (close assistant first if open).
- **Acceptance criteria**:
  - [ ] Snackbar appears on top of reading screen, does not interrupt RSVP timer
  - [ ] All three actions work correctly
  - [ ] Auto-dismisses at 6s
  - [ ] Custom neumorphic snackbar (no Material widget) per Rule 15
  - [ ] If AssistantSheet open: close it before showing snackbar
  - [ ] No payload contents in any visible UI text beyond preview (use `payload.displayTitle`)
  - [ ] `dart analyze` reports 0 issues
- **Principles**: DP1, Rule 49
- **Effort**: M (~1.5 hr)
- **Depends on**: TASK-410

### TASK-414: Add /share-receive, /share-preview, /read-shared-url routes
- **Priority**: 3
- **Files**: `MODIFY: lib/router.dart`
- **Action**: Add three new GoRoute entries per copilot patch route map. `/share-receive` → `ShareReceiveScreen`. `/share-preview` → `SharePreviewSheet` as modal page. `/read-shared-url?hash=<hash>` → `ParallaxReadingScreen` with `sharedUrlHash` parameter and `wallFoldTransitionPage` transition.
- **Acceptance criteria**:
  - [ ] All three routes registered
  - [ ] `/read-shared-url` reads `hash` from query parameters
  - [ ] `/share-preview` accepts `SharedPayload` via `state.extra`
  - [ ] `wallFoldTransitionPage` used for `/read-shared-url`
  - [ ] Existing routes unaffected
  - [ ] `dart analyze lib/` reports 0 issues
- **Principles**: None (routing)
- **Effort**: S (~20 min)
- **Depends on**: TASK-411, TASK-412

### TASK-415: Extend ParallaxReadingScreen for shared URL source
- **Priority**: 4
- **Files**: `MODIFY: lib/screens/parallax_reading_screen.dart`
- **Action**: Add `sharedUrlHash` parameter (nullable String). Add `_isSharedUrl` getter mirroring `_isInstapaper` and `_isClipboard`. In init flow: load entry from `SharedUrlCache.get(hash)` → if `cachedText`, tokenize → if not, fetch via v6 `InstaparserService.extractArticle(entry.url)` → cache result via `SharedUrlCache.update`. Seek to `entry.progress * wordCount`. On pause: `SharedUrlCache.updateProgress(hash, currentProgress)`.
- **Acceptance criteria**:
  - [ ] `sharedUrlHash` parameter added with null default
  - [ ] `_isSharedUrl` guard implemented
  - [ ] Cached entries open immediately without network
  - [ ] Uncached entries fetch via v6 InstaparserService (Rule 48)
  - [ ] Progress restored on open
  - [ ] Progress saved on pause (local only, no remote sync)
  - [ ] All v3–v7 features work identically (gestures, ContextReveal, WPM, sheet, assistant)
  - [ ] If fetch fails: navigate back to `/share-preview` with error
  - [ ] `dart analyze` reports 0 issues
- **Principles**: DP2, DP5 (carryover from v6 — same reading experience)
- **Effort**: M (~1.5 hr)
- **Depends on**: TASK-402, TASK-414

### TASK-416: Create RecentlySharedSection library widget
- **Priority**: 4
- **Files**: `CREATE: lib/widgets/recently_shared_section.dart`, `MODIFY: lib/screens/library_screen.dart`
- **Action**: New collapsible library section using v6 `LibrarySection` shell. Watches `recentlySharedProvider` (Riverpod, lists from `SharedUrlCache`). Renders v6 `ArticleCard` per entry. Long-press card → context menu with [Open][Remove from history][Clear all shared]. Section only renders when ≥1 entry. Inserts between Instapaper section and Local Files section in library screen.
- **Acceptance criteria**:
  - [ ] Section hidden when cache empty
  - [ ] Section shows correct count of entries (≤ cap)
  - [ ] ArticleCard reused unchanged (Rule 48 spirit — reuse v6)
  - [ ] Tap → `/read-shared-url?hash=<hash>`
  - [ ] Long-press → context menu with 3 actions
  - [ ] "Remove" updates section immediately (Riverpod auto-refresh)
  - [ ] "Clear all" prompts confirmation, then clears
  - [ ] Sits between Instapaper and Local Files sections
  - [ ] `dart analyze` reports 0 issues
- **Principles**: DP4, DP6
- **Effort**: M (~1 hr)
- **Depends on**: TASK-402, TASK-415

### TASK-417: Create Riverpod providers
- **Priority**: 4
- **Files**: `CREATE: lib/providers/share_intent_provider.dart`
- **Action**: Define: `initialSharedPayloadProvider` (Provider<SharedPayload?>, set in main.dart), `shareIntentServiceProvider` (Provider<ShareIntentService>), `shareIntentRouterProvider` (Provider<ShareIntentRouter>), `recentlySharedProvider` (FutureProvider<List<SharedUrlEntry>>, reads SharedUrlCache.list, auto-refreshes when cache changes via simple version counter). `recentlySharedNotifierProvider` for mutations (add/remove/clearAll).
- **Acceptance criteria**:
  - [ ] All providers declared with correct types
  - [ ] `recentlySharedProvider` refreshes after add/remove/clearAll
  - [ ] No global state — all access through providers
  - [ ] Auto-dispose where appropriate (Rule 41 spirit)
  - [ ] `dart analyze` reports 0 issues
  - [ ] Unit tests with ProviderContainer
- **Principles**: None (state)
- **Effort**: S (~45 min)
- **Depends on**: TASK-402, TASK-408, TASK-410

---

## Sprint 4: Settings, Polish, Verification

### TASK-418: Settings Screen — Sharing Section
- **Priority**: 5
- **Files**: `MODIFY: lib/screens/settings_screen.dart`
- **Action**: Add "Sharing" section with: toggle for `universalShareEnabled`, editable list of trusted domains (add/remove buttons), dropdown for `recentlySharedCap` ([5, 10, 20, 50, 100]), "Clear shared history" button (calls `SharedUrlCache.clearAll`).
- **Acceptance criteria**:
  - [ ] Toggle binds to `AppConfig.universalShareEnabled`
  - [ ] Domain list shows current trusted domains; add/remove updates AppConfig
  - [ ] Add domain validates input is a valid host (no protocol, no path)
  - [ ] Cap dropdown updates `AppConfig.recentlySharedCap`
  - [ ] Cap change shrinks cache if new cap < current count (FIFO eviction)
  - [ ] "Clear shared history" prompts confirmation, then clears cache
  - [ ] No raw Material widgets (Rule 15)
  - [ ] `dart analyze` reports 0 issues
- **Principles**: None (settings UI)
- **Effort**: M (~1 hr)
- **Depends on**: TASK-403, TASK-417

### TASK-419: Disable share intent when toggle is off
- **Priority**: 5
- **Files**: `MODIFY: lib/services/share_intent_router.dart`
- **Action**: At top of `handle()`, check `AppConfig.universalShareEnabled`. If false: silently drop the payload (no UI, no logs beyond metadata). Native intent filter remains registered (cannot be runtime-disabled), so the app may still launch from share — in that cold-start case, just navigate to library instead of share destination.
- **Acceptance criteria**:
  - [ ] Disable toggle → share intent triggers no UI navigation
  - [ ] Cold-start with toggle off → app launches to library, not share-receive
  - [ ] No payload contents logged
  - [ ] Re-enabling toggle works without restart
  - [ ] `dart analyze` reports 0 issues
- **Principles**: User control
- **Effort**: XS (~15 min)
- **Depends on**: TASK-410, TASK-418

### TASK-420: Web/desktop graceful degradation audit
- **Priority**: 5
- **Files**: All v8 UI files
- **Action**: Verify on Linux desktop and Web build: app launches without errors. Settings → Sharing section is HIDDEN entirely (use `kIsWeb || Platform.isLinux || Platform.isMacOS || Platform.isWindows` guard). RecentlySharedSection is hidden (cache always empty). No share-related code paths execute. Run `flutter analyze` and `flutter build web` and `flutter build linux` (or whichever desktop is available).
- **Acceptance criteria**:
  - [ ] `flutter build web` succeeds
  - [ ] `flutter build <desktop>` succeeds
  - [ ] Web build has no Sharing section in Settings
  - [ ] Web build has no RecentlySharedSection in library
  - [ ] No console errors on web/desktop launch
  - [ ] No platform channel exceptions
- **Principles**: Cross-platform safety
- **Effort**: S (~30 min)
- **Depends on**: TASK-416, TASK-418

### TASK-421: Integration test suite
- **Priority**: 6
- **Files**: `CREATE: test/integration/share_flow_test.dart`
- **Action**: Implement integration tests for the 14 scenarios from spec's Integration Test Scenarios table. Use mocked `ShareIntentService` (override `shareIntentServiceProvider`). Mock `InstaparserService` for URL fetches. Verify routing decisions match decision table.
- **Acceptance criteria**:
  - [ ] All 14 scenarios from spec implemented
  - [ ] All tests pass
  - [ ] Test for cold-start payload dedup (Rule 44)
  - [ ] Test for active-reading snackbar (Rule 49)
  - [ ] Test for trusted-domain auto-confirm vs untrusted preview (Rule 45)
  - [ ] Test for log scrubbing — no payload text in captured logs (Rule 46)
  - [ ] `flutter test` reports all green
- **Principles**: Verification
- **Effort**: L (~2.5 hr)
- **Depends on**: TASK-415, TASK-416, TASK-419

### TASK-422: Final cross-cutting verification
- **Priority**: 6
- **Files**: All
- **Action**:
  ```bash
  dart analyze lib/
  flutter test
  grep -ri "print\|debugPrint" lib/services/share_intent_*.dart lib/services/shared_url_cache.dart  # confirm only metadata logging
  flutter build apk --debug
  flutter build ios --no-codesign
  ```
  Manual smoke test on Android emulator: cold-start text share, warm-start URL share, trusted vs untrusted, recently shared section behavior, settings toggle. iOS smoke test on simulator (extension may need device for full validation).
- **Acceptance criteria**:
  - [ ] `dart analyze lib/` → zero issues
  - [ ] `flutter test` → all pass
  - [ ] No raw `print()` calls in v8 service files
  - [ ] Android APK builds clean
  - [ ] iOS build succeeds
  - [ ] Manual smoke test passes on Android emulator (logged in TASK comment)
  - [ ] iOS smoke test passes on simulator OR documented as device-required
- **Principles**: Verification
- **Effort**: M (~1 hr)
- **Depends on**: TASK-421

---

## Dependency Graph

```
TASK-400 (deps) ──┬── TASK-401 (SharedPayload model) ──┬── TASK-402 (cache + entry)
                  │                                     │
                  ├── TASK-403 (AppConfig)              │
                  │                                     │
                  ├── TASK-404 (Android native) ────────┤
                  │                                     │
                  └── TASK-405 (iOS extension) ─ TASK-406 (iOS host) ─ TASK-407 (verify)
                                                                              │
TASK-401, 402, 403, 404, 406 ──→ TASK-408 (ShareIntentService)               │
                                            │                                 │
                                            └── TASK-409 (main wiring)        │
                                                       │                      │
                              ┌────────────────────────┴──────────────────────┘
                              │
TASK-402, 403, 408 ──→ TASK-410 (Router) ──┬── TASK-411 (ShareReceiveScreen)
                                            ├── TASK-412 (SharePreviewSheet)
                                            ├── TASK-413 (active-reading snackbar)
                                            └── TASK-414 (routes)
                                                       │
                              TASK-414 ──→ TASK-415 (ParallaxReadingScreen ext)
                              TASK-402, 415 ──→ TASK-416 (RecentlySharedSection)
                              TASK-402, 408, 410 ──→ TASK-417 (Riverpod providers)

TASK-403, 417 ──→ TASK-418 (Settings) ──→ TASK-419 (disable toggle behavior)
TASK-416, 418 ──→ TASK-420 (web/desktop audit)
TASK-415, 416, 419 ──→ TASK-421 (integration tests) ──→ TASK-422 (final verify)
```

## Effort Distribution

- XS: 2 tasks
- S: 9 tasks
- M: 10 tasks
- L: 2 tasks
- **Total tasks**: 23
- **Estimated total**: ~22–25 hours (3–4 sprints of focused work)

## Sprint Plan

| Sprint | Tasks | Focus | Approx. duration |
|---|---|---|---|
| **1** | TASK-400 to TASK-403 | Foundation: deps, models, config | ~2.5 hr |
| **2** | TASK-404 to TASK-409 | Native bridge + service layer | ~7 hr (iOS dominates) |
| **3** | TASK-410 to TASK-417 | Router, UI, reading integration | ~9 hr |
| **4** | TASK-418 to TASK-422 | Settings, polish, verification | ~5 hr |
