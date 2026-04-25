# Speedy Boy v6.0 — Task Backlog

**Generated**: 2026-04-06
**Spec version**: 6.0.0 (Instapaper Integration)
**Codebase scanned**: c:\Users\Matthew\speedy-boyv3

## Scan Summary

- **Implemented**: 0 / 13 v6 priorities
- **Partial**: 0 / 13 v6 priorities
- **Not started**: 13 / 13 v6 priorities
- **Total tasks generated**: 24

## Blockers & Ambiguities

1. **Instapaper API credentials required before any testing.** Request Full API access at https://www.instapaper.com/api. Approval may take days. TASK-300 adds deps but real API testing blocked until credentials arrive. Mock tests (TASK-308) can proceed independently.

2. **Instaparser API key required for fallback extraction.** Sign up at https://instaparser.com for a Bearer token. TASK-305 implements the service but can't integration-test without a key.

3. **OAuth 1.0a signing approach undecided.** The `oauth1` package exists but may be overkill for a single xAuth POST. TASK-303 should evaluate: use `oauth1` package OR hand-roll HMAC-SHA1 signing (it's one endpoint). Decision made during implementation.

4. **`http` package already in pubspec.** No additional HTTP dependency needed. TASK-300 only adds `flutter_secure_storage` and HTML processing.

5. **`pull-to-refresh` in library uses Rule 15 (no raw Material widgets).** The spec says pull-to-refresh triggers Instapaper sync, but `RefreshIndicator` is forbidden. TASK-313 must implement a custom pull-to-refresh or use the existing neumorphic gesture pattern.

6. **Swipe-to-archive/delete may conflict with v4 gesture system.** The library screen uses horizontal drag for article card actions, but the reading screen's `onHorizontalDragEnd` is for sentence navigation. Library ≠ reading screen, so no conflict — but verify gesture handlers don't leak. TASK-317 addresses this.

---

## Sprint 1: Foundation — Dependencies, Models, Config

### TASK-300: Add Instapaper dependencies to pubspec.yaml
- **Priority**: 0 (prerequisite)
- **Files**: `MODIFY: pubspec.yaml`
- **Action**: Add `flutter_secure_storage` and `html` (or `html_unescape`) to dependencies. Evaluate `oauth1` package — add if choosing package-based OAuth signing. Run `flutter pub get`.
- **Acceptance criteria**:
  - [ ] `flutter_secure_storage` in pubspec.yaml dependencies
  - [ ] HTML processing package in pubspec.yaml dependencies
  - [ ] `flutter pub get` completes without errors
  - [ ] `dart analyze lib/` reports 0 issues (no regression)
- **Principles**: None (infrastructure)
- **Effort**: XS (~15 min)
- **Depends on**: Nothing

### TASK-301: Create InstapaperBookmark model
- **Priority**: 0 (prerequisite)
- **Files**: `CREATE: lib/models/instapaper_bookmark.dart`
- **Action**: Create model with all fields from spec: `bookmarkId`, `title`, `url`, `description`, `progress`, `progressTimestamp`, `savedAt`, `starred`, `domain` (computed from URL), `cachedText`, `wordCount`, `words`. Include `fromJson()`, `toJson()`, `copyWith()`. Include static helpers: `wordIndexToProgress(int, int)` and `progressToWordIndex(double, int)`.
- **Acceptance criteria**:
  - [ ] All 12 fields declared with correct types and nullability
  - [ ] `fromJson` handles all fields including nullable ones
  - [ ] `toJson` round-trips correctly (encode → decode → compare)
  - [ ] `domain` extracted from URL via `Uri.parse(url).host`
  - [ ] `wordIndexToProgress(50, 100)` returns `0.5`
  - [ ] `progressToWordIndex(0.5, 100)` returns `50`
  - [ ] `progressToWordIndex(0.0, 100)` returns `0`
  - [ ] `wordIndexToProgress(0, 0)` returns `0.0` (no divide-by-zero)
  - [ ] `dart analyze` reports 0 issues on this file
- **Principles**: None (data model)
- **Effort**: S (~25 min)
- **Depends on**: Nothing

### TASK-319: AppConfig additions for Instapaper
- **Priority**: 0 (prerequisite)
- **Files**: `MODIFY: lib/store/models.dart`, `MODIFY: lib/store/config.dart`
- **Action**: Add `instapaperConnected` (bool, default false), `archiveOnFinish` (bool, default false), `showArchivedArticles` (bool, default false) to AppConfig. Add `copyWith` support. Add `setInstapaperConnected()`, `setArchiveOnFinish()`, `setShowArchivedArticles()` to ConfigNotifier following `_synchronized` pattern. Ensure JSON backward compatibility (missing keys → defaults).
- **Acceptance criteria**:
  - [ ] Three new fields in AppConfig with correct defaults
  - [ ] `copyWith` supports all three new fields
  - [ ] `toJson`/`fromJson` round-trips correctly
  - [ ] Missing keys in JSON → defaults (backward compatible)
  - [ ] Three new setter methods in ConfigNotifier follow `_synchronized` pattern
  - [ ] `dart analyze lib/` reports 0 issues
- **Principles**: None (foundation)
- **Effort**: S (~20 min)
- **Depends on**: Nothing

---

## Sprint 2: Auth & Service Layer

### TASK-302: Create SecureStorageService wrapper
- **Priority**: 1
- **Files**: `CREATE: lib/services/secure_storage.dart`
- **Action**: Thin wrapper around `FlutterSecureStorage`. Methods: `saveOAuthTokens(token, secret)`, `getOAuthTokens()` → `(String, String)?`, `deleteOAuthTokens()`, `saveInstaparserKey(key)`, `getInstaparserKey()` → `String?`, `deleteInstaparserKey()`. Each method handles `PlatformException` gracefully (return null on read failure).
- **Acceptance criteria**:
  - [ ] All 6 methods implemented with correct signatures
  - [ ] `getOAuthTokens()` returns null when no tokens stored
  - [ ] `PlatformException` handled gracefully (no crashes)
  - [ ] No credentials logged (Rule 29)
  - [ ] `dart analyze` reports 0 issues
- **Principles**: DP3
- **Effort**: XS (~15 min)
- **Depends on**: TASK-300

### TASK-303: Create InstapaperAuth service
- **Priority**: 1
- **Files**: `CREATE: lib/services/instapaper_auth.dart`
- **Action**: Implement xAuth flow. `authenticate(email, password)` → `POST /api/1/oauth/access_token` with OAuth 1.0a signature + xAuth params. Store tokens via `SecureStorageService`. `verifyCredentials()` → `POST /api/1/account/verify_credentials`. `disconnect()` → delete tokens + clear cache. `isConnected` → check secure storage. Consumer key/secret from `String.fromEnvironment('INSTAPAPER_KEY')` and `String.fromEnvironment('INSTAPAPER_SECRET')`.
- **Acceptance criteria**:
  - [ ] `authenticate()` sends correct xAuth POST with OAuth 1.0a signature
  - [ ] On success, stores tokens in secure storage and sets `instapaperConnected = true`
  - [ ] Email/password not stored anywhere beyond method scope
  - [ ] Consumer key/secret from `String.fromEnvironment` only
  - [ ] `verifyCredentials()` returns user info or throws on invalid tokens
  - [ ] `disconnect()` deletes tokens, clears cache, sets `instapaperConnected = false`
  - [ ] `isConnected` checks secure storage
  - [ ] 401 response handled with clear error message
  - [ ] Network error handled with clear error message
  - [ ] `dart analyze` reports 0 issues
- **Principles**: DP3
- **Effort**: M (~1.5 hr)
- **Depends on**: TASK-302, TASK-319

### TASK-304: Create InstapaperService
- **Priority**: 2
- **Files**: `CREATE: lib/services/instapaper_service.dart`
- **Action**: API client using stored OAuth tokens. All requests OAuth 1.0a signed. Methods: `listBookmarks({folder, limit})` → parse to `List<InstapaperBookmark>`, `getArticleText(bookmarkId)` → HTML string, `updateReadProgress(bookmarkId, progress)`, `archiveBookmark(bookmarkId)`, `unarchiveBookmark(bookmarkId)`, `deleteBookmark(bookmarkId)`. Handle 401 → re-auth needed. Handle 429/5xx → exponential backoff (1s, 2s, 4s, max 3 retries). Handle network unreachable → return null/empty.
- **Acceptance criteria**:
  - [ ] All 6 API methods implemented with correct endpoint URLs
  - [ ] Every request signed with OAuth 1.0a
  - [ ] `listBookmarks` parses response into `List<InstapaperBookmark>`
  - [ ] 401 sets auth state to disconnected
  - [ ] 429/5xx retries with exponential backoff (max 3)
  - [ ] Network errors return null, don't throw
  - [ ] `updateReadProgress` never throws (fire-and-forget safe — Rule 33)
  - [ ] 500-bookmark limit handled (note if truncated)
  - [ ] `dart analyze` reports 0 issues
- **Principles**: DP1, DP3
- **Effort**: L (~2.5 hr)
- **Depends on**: TASK-302, TASK-301

### TASK-305: Create InstaparserService (fallback extractor)
- **Priority**: 3
- **Files**: `CREATE: lib/services/instaparser_service.dart`
- **Action**: Simple REST client. `extractArticle(url)` → `POST https://instaparser.com/api/1/article` with Bearer token from secure storage. Returns `({String title, String content, int wordCount})?` record or null on failure. Handle 402 (out of credits) gracefully.
- **Acceptance criteria**:
  - [ ] `extractArticle` sends correct POST with Bearer auth
  - [ ] Parses response JSON into title + content + wordCount
  - [ ] Returns null on failure (not throws)
  - [ ] Handles 402 (credit exhaustion) without crash
  - [ ] Bearer token from `SecureStorageService.getInstaparserKey()`
  - [ ] `dart analyze` reports 0 issues
- **Principles**: DP1
- **Effort**: S (~30 min)
- **Depends on**: TASK-302

### TASK-307: Create HtmlTextExtractor
- **Priority**: 2
- **Files**: `CREATE: lib/core/html_text_extractor.dart`
- **Action**: `htmlToPlainText(String html)` — strip all tags, convert `<p>`, `<br>`, `<h*>` to `\n\n`, decode HTML entities, collapse whitespace, trim. `htmlToWords(String html)` — calls `htmlToPlainText` then tokenizes using the same sentence-splitting pipeline as `ClipboardDocument._textToSentences()`. Returns `ExtractedDocument` compatible with existing reading engine. Heavy processing via `Isolate.run()` (Rule 11).
- **Acceptance criteria**:
  - [ ] `<p>`, `<br>`, `<h1>`–`<h6>` converted to paragraph breaks
  - [ ] All other tags stripped
  - [ ] `&amp;`, `&lt;`, `&gt;`, `&quot;`, `&#39;`, `&nbsp;` decoded correctly
  - [ ] Multiple whitespace collapsed to single space
  - [ ] `htmlToWords` returns `ExtractedDocument` with valid sentences
  - [ ] Empty HTML input returns empty document (no crash)
  - [ ] Processing runs in Isolate (Rule 11)
  - [ ] `dart analyze` reports 0 issues
- **Principles**: DP5
- **Effort**: S (~30 min)
- **Depends on**: TASK-300

### TASK-306: Create InstapaperCache
- **Priority**: 2
- **Files**: `CREATE: lib/services/instapaper_cache.dart`
- **Action**: JSON file cache in `<appSupport>/instapaper_cache/`. Methods: `cacheBookmarks(List<InstapaperBookmark>)`, `getCachedBookmarks()` → `List<InstapaperBookmark>`, `cacheArticleText(int bookmarkId, String text, List<String> words, int wordCount)`, `getCachedArticle(int bookmarkId)` → cached article data or null, `clearCache()` → delete entire directory. All file I/O in `Isolate.run()` (Rule 11).
- **Acceptance criteria**:
  - [ ] Bookmark list cached at `instapaper_cache/bookmarks.json`
  - [ ] Article text cached at `instapaper_cache/articles/<bookmarkId>.json`
  - [ ] `getCachedBookmarks` returns empty list when no cache exists
  - [ ] `getCachedArticle` returns null when no cache exists
  - [ ] `clearCache` deletes entire `instapaper_cache/` directory
  - [ ] All file I/O runs in `Isolate.run()` (Rule 11)
  - [ ] Corrupt cache file → graceful fallback (empty list or null)
  - [ ] `dart analyze` reports 0 issues
- **Principles**: DP2
- **Effort**: M (~1 hr)
- **Depends on**: TASK-301

---

## Sprint 3: Service Tests

### TASK-308A: Unit tests — InstapaperBookmark model
- **Priority**: 2
- **Files**: `CREATE: test/models/instapaper_bookmark_test.dart`
- **Action**: Test `fromJson`/`toJson` round-trip, `copyWith`, domain extraction from various URLs, progress mapping edge cases (0 words, 1 word, boundary values).
- **Acceptance criteria**:
  - [ ] JSON round-trip test passes
  - [ ] Domain extraction from `https://www.example.com/path` → `www.example.com`
  - [ ] Domain extraction from malformed URL returns null
  - [ ] `copyWith` preserves unchanged fields
  - [ ] Progress mapping tests cover 0-word, 1-word, boundary cases
  - [ ] All tests pass
- **Principles**: None
- **Effort**: S (~20 min)
- **Depends on**: TASK-301

### TASK-308B: Unit tests — HtmlTextExtractor
- **Priority**: 2
- **Files**: `CREATE: test/core/html_text_extractor_test.dart`
- **Action**: Test HTML stripping, entity decoding, paragraph break preservation, empty input, malformed HTML, nested tags, script/style tag removal.
- **Acceptance criteria**:
  - [ ] `<p>Hello</p><p>World</p>` → `"Hello\n\nWorld"`
  - [ ] `<script>...</script>` content removed entirely
  - [ ] `<style>...</style>` content removed entirely
  - [ ] `&amp;&lt;&gt;` → `&<>`
  - [ ] Empty string → empty string
  - [ ] Deeply nested tags → flattened text
  - [ ] All tests pass
- **Principles**: None
- **Effort**: S (~20 min)
- **Depends on**: TASK-307

### TASK-308C: Unit tests — InstapaperAuth and InstapaperService
- **Priority**: 3
- **Files**: `CREATE: test/services/instapaper_auth_test.dart`, `CREATE: test/services/instapaper_service_test.dart`
- **Action**: Mock HTTP client. Test: xAuth request format, token storage on success, 401 handling, network error handling. Test: bookmark list parsing, progress update request format, archive/delete calls, retry with backoff on 429.
- **Acceptance criteria**:
  - [ ] xAuth request includes correct OAuth signature parameters
  - [ ] Successful auth stores tokens in secure storage mock
  - [ ] 401 propagates as auth error
  - [ ] Network error propagates as connectivity error
  - [ ] Bookmark list parsing handles empty list
  - [ ] Bookmark list parsing handles 500 items
  - [ ] 429 triggers retry (verified via mock call count)
  - [ ] All tests pass
- **Principles**: None
- **Effort**: M (~1 hr)
- **Depends on**: TASK-303, TASK-304

### TASK-308D: Unit tests — InstapaperCache
- **Priority**: 3
- **Files**: `CREATE: test/services/instapaper_cache_test.dart`
- **Action**: Test cache write/read round-trip, clear cache, corrupt file handling, missing directory creation.
- **Acceptance criteria**:
  - [ ] Bookmark cache write → read returns same data
  - [ ] Article cache write → read returns same data
  - [ ] `clearCache` → subsequent reads return empty/null
  - [ ] Corrupt JSON file → returns empty list (no crash)
  - [ ] All tests pass
- **Principles**: None
- **Effort**: S (~20 min)
- **Depends on**: TASK-306

---

## Sprint 4: Library UI — Widgets

### TASK-309: Create LibrarySection widget
- **Priority**: 1
- **Files**: `CREATE: lib/widgets/library_section.dart`
- **Action**: Reusable collapsible section with header (title + optional trailing action widget) and vertically-stacked children. Header text: `SpeedyBoyTypography.shellCaption` + `shellTextSecondary`. Collapse animation: 200ms Curves.easeInOut with reduced motion check (Rule 5). Collapse state ephemeral (in-memory). Only renders if children list is non-empty (DP4).
- **Acceptance criteria**:
  - [ ] Section header shows title in `shellTextSecondary`
  - [ ] Optional trailing action widget renders
  - [ ] Tap header toggles collapse/expand
  - [ ] Collapse animation 200ms with `Curves.easeInOut`
  - [ ] Reduced motion check — instant toggle when enabled (Rule 5)
  - [ ] Empty children list → renders nothing
  - [ ] Uses shell surface tokens only (Rule 7)
  - [ ] No hardcoded TextStyle (Rule 2)
  - [ ] `dart analyze` reports 0 issues
- **Principles**: DP4
- **Effort**: S (~30 min)
- **Depends on**: Nothing

### TASK-310: Create ArticleCard widget
- **Priority**: 1
- **Files**: `CREATE: lib/widgets/article_card.dart`
- **Action**: Card showing title (max 2 lines, ellipsis), domain + word count subtitle, progress bar (only when > 0). Surface: `SpeedyBoyDecorations.raisedDecoration(SpeedyBoyTokens.shellBase, NeumorphicSize.medium)`. Tap callback for opening. Swipe-left reveal for archive/delete buttons (TASK-317 wires API calls). Long-press context menu. Semantics: `"$title from $domain, $progress percent read"`.
- **Acceptance criteria**:
  - [ ] Title renders in `SpeedyBoyTypography.shellBody` semiBold, max 2 lines
  - [ ] Subtitle shows domain + word count in `shellTextSecondary`
  - [ ] Progress bar visible only when `progress > 0.0`
  - [ ] Progress bar uses `shellAccent` fill
  - [ ] Surface uses `SpeedyBoyDecorations.raisedDecoration` (Rule 3)
  - [ ] Tap callback fires on tap
  - [ ] Swipe left reveals archive + delete action buttons
  - [ ] Long-press shows context menu (Archive, Delete, Open in Browser)
  - [ ] Semantics label: "$title from $domain, $progressPercent percent read"
  - [ ] Shell surface tokens only (Rule 7)
  - [ ] No hardcoded colors, TextStyle, or BoxDecoration (Rules 1, 2, 3)
  - [ ] Loading state uses neumorphic pulse, not CircularProgressIndicator (Rule 15)
  - [ ] `dart analyze` reports 0 issues
- **Principles**: DP4
- **Effort**: M (~1 hr)
- **Depends on**: TASK-301

### TASK-311: Create SourceAddSheet bottom sheet
- **Priority**: 1
- **Files**: `CREATE: lib/widgets/source_add_sheet.dart`
- **Action**: Bottom sheet with tappable rows: "Connect Instapaper" (if not connected) / "Instapaper Connected ✓" (if connected), "Browse Local Files", "Paste from Clipboard". Each row: icon + label. Shell surface tokens. Callbacks for each action. Dismiss on action.
- **Acceptance criteria**:
  - [ ] Shows "Connect Instapaper" when `instapaperConnected == false`
  - [ ] Shows "Instapaper Connected ✓" (non-tappable) when connected
  - [ ] "Browse Local Files" option present
  - [ ] "Paste from Clipboard" option present
  - [ ] Shell surface tokens used (Rule 7)
  - [ ] Bottom sheet auto-dismisses after action
  - [ ] `dart analyze` reports 0 issues
- **Principles**: DP4
- **Effort**: S (~30 min)
- **Depends on**: Nothing

### TASK-312: Create InstapaperLoginModal
- **Priority**: 2
- **Files**: `CREATE: lib/widgets/instapaper_login_modal.dart`
- **Action**: Modal dialog with email + password fields. Connect button disabled until both non-empty. On submit: call `InstapaperAuth.authenticate()`. States: idle, connecting (neumorphic pulse), error (inline message), success (auto-dismiss). Credentials in local `TextEditingController` only — never in state/provider (Rule 29). Dispose controllers on widget dispose.
- **Acceptance criteria**:
  - [ ] Email field: `TextInputType.emailAddress`, `autocorrect: false`
  - [ ] Password field: `obscureText: true`
  - [ ] Connect button disabled until both fields non-empty
  - [ ] Loading state: neumorphic pulse (Rule 15)
  - [ ] Error state: inline error message below fields
  - [ ] Success: auto-dismiss modal
  - [ ] Credentials in local `TextEditingController` only (Rule 29)
  - [ ] Controllers disposed in widget `dispose()`
  - [ ] Shell surface tokens (Rule 7)
  - [ ] `dart analyze` reports 0 issues
- **Principles**: DP3
- **Effort**: M (~45 min)
- **Depends on**: TASK-303

---

## Sprint 5: Library Redesign & Provider

### TASK-314: Create Instapaper bookmark Riverpod provider
- **Priority**: 2
- **Files**: `CREATE: lib/providers/instapaper_provider.dart`
- **Action**: Riverpod AsyncNotifier or FutureProvider managing bookmark list state. Auto-loads from cache on startup. `refresh()` → fetch from API + merge with cache. `archive(bookmarkId)` → API call + update local state. `delete(bookmarkId)` → API call + remove from state + clear article cache. Watches auth state — clears when disconnected. Auto-dispose when library screen unmounts.
- **Acceptance criteria**:
  - [ ] Provider loads cached bookmarks on startup (no network needed)
  - [ ] `refresh()` fetches from API and merges with cache
  - [ ] `archive(id)` calls API and removes from bookmark list
  - [ ] `delete(id)` calls API, removes from list, clears article cache
  - [ ] Auth disconnect → clears provider state
  - [ ] Provider is auto-dispose
  - [ ] `dart analyze` reports 0 issues
- **Principles**: DP2, DP4
- **Effort**: M (~1 hr)
- **Depends on**: TASK-304, TASK-306

### TASK-313: Redesign library screen with sections
- **Priority**: 1
- **Files**: `MODIFY: lib/screens/library_screen.dart`
- **Action**: Refactor flat file list into sectioned layout using `LibrarySection`. Section order: Instapaper (if connected + has content) → Local Files → Clipboard button. Add [+] button to app bar (opens `SourceAddSheet`). Add ↻ refresh button on Instapaper section header. Instapaper section watches `instapaperProvider`. Empty Instapaper section: "No unread articles". Disconnected: section hidden entirely. Custom pull-to-refresh (DP4, Rule 15 — no RefreshIndicator). Preserve all existing functionality.
- **Acceptance criteria**:
  - [ ] Instapaper section visible when connected + has bookmarks
  - [ ] Instapaper section hidden when disconnected
  - [ ] Instapaper section shows "No unread articles" when connected + empty
  - [ ] ↻ button triggers `instapaperProvider.refresh()`
  - [ ] [+] button in app bar opens `SourceAddSheet`
  - [ ] Local Files section shows existing PDF list (no regression)
  - [ ] Clipboard button at bottom (no regression)
  - [ ] No `RefreshIndicator` used (Rule 15)
  - [ ] Existing error badge preserved
  - [ ] Existing clipboard hint overlay preserved
  - [ ] `dart analyze` reports 0 issues
- **Principles**: DP4
- **Effort**: L (~2 hr)
- **Depends on**: TASK-309, TASK-310, TASK-311, TASK-314

---

## Sprint 6: Reading Integration & Sync

### TASK-315A: Add `/read-instapaper` route
- **Priority**: 2
- **Files**: `MODIFY: lib/navigation/app_router.dart`
- **Action**: Add new route `/read-instapaper` that passes `InstapaperBookmark` via `extra` to `ParallaxReadingScreen`. Uses `wallFoldTransitionPage`. Sets `filePath: 'instapaper://${bookmark.bookmarkId}'`.
- **Acceptance criteria**:
  - [ ] Route `/read-instapaper` registered in GoRouter
  - [ ] `extra` cast to `InstapaperBookmark`
  - [ ] Uses `wallFoldTransitionPage` transition
  - [ ] `filePath` formatted as `instapaper://<bookmarkId>`
  - [ ] `dart analyze` reports 0 issues
- **Principles**: DP5
- **Effort**: XS (~10 min)
- **Depends on**: TASK-301

### TASK-315B: Wire Instapaper articles into reading viewport
- **Priority**: 3
- **Files**: `MODIFY: lib/screens/parallax_reading_screen.dart`
- **Action**: Add `instapaperBookmark` parameter to `ParallaxReadingScreen`. Add `_isInstapaper` guard (same pattern as `_isClipboard`). In `initState`, if `_isInstapaper`: check cached text → if not cached, fetch via `InstapaperService.getArticleText()` → if fails, fallback to `InstaparserService.extractArticle()` → strip HTML via `HtmlTextExtractor.htmlToWords()` → cache result → seek to progress position. All existing features work unchanged.
- **Acceptance criteria**:
  - [ ] `instapaperBookmark` parameter added to widget
  - [ ] `_isInstapaper` guard works like `_isClipboard`
  - [ ] Cached text used when available (no network call)
  - [ ] `get_text` called first when no cache
  - [ ] Instaparser fallback when `get_text` fails (Rule 31)
  - [ ] HTML stripped via `HtmlTextExtractor` (Rule 11 — Isolate)
  - [ ] Result cached via `InstapaperCache` (Rule 30)
  - [ ] Seeks to `progressToWordIndex` position on open
  - [ ] All gestures, ContextReveal, WPM dial, hints work unchanged
  - [ ] Error on fetch failure → navigate back to library
  - [ ] `dart analyze` reports 0 issues
- **Principles**: DP1, DP2, DP5
- **Effort**: M (~1.5 hr)
- **Depends on**: TASK-304, TASK-305, TASK-307, TASK-306, TASK-315A

### TASK-316: Progress sync on pause/finish
- **Priority**: 3
- **Files**: `MODIFY: lib/screens/parallax_reading_screen.dart`
- **Action**: On pause (when `_isInstapaper`): compute `wordIndexToProgress(currentIndex, totalWords)` → fire-and-forget `InstapaperService.updateReadProgress()`. On finish: if `AppConfig.archiveOnFinish` → call `InstapaperService.archiveBookmark()` → show transient banner "Archived in Instapaper" with [Undo] for 5 seconds → undo calls `unarchiveBookmark()`. Banner auto-dismisses after 5s.
- **Acceptance criteria**:
  - [ ] Progress sync on pause — fire-and-forget, no await in gesture handler (Rule 33)
  - [ ] Progress value computed correctly: `wordIndex / totalWords`
  - [ ] On finish + `archiveOnFinish == true` → archive API called
  - [ ] Banner shown: "Archived in Instapaper" with Undo
  - [ ] Undo calls `unarchiveBookmark()`
  - [ ] Banner auto-dismisses after 5 seconds
  - [ ] On finish + `archiveOnFinish == false` → no archive, no banner
  - [ ] Sync failure silently logged (no UI error)
  - [ ] `dart analyze` reports 0 issues
- **Principles**: DP5 (same reading experience)
- **Effort**: M (~45 min)
- **Depends on**: TASK-315B

### TASK-317: Swipe-to-archive and swipe-to-delete on article cards
- **Priority**: 4
- **Files**: `MODIFY: lib/widgets/article_card.dart`, `MODIFY: lib/providers/instapaper_provider.dart` (if needed)
- **Action**: Wire swipe actions to API. Swipe left → call `instapaperProvider.archive(bookmarkId)` → remove from list → brief "Archived" notification with Undo. Swipe right → confirmation dialog "Permanently delete from Instapaper? This cannot be undone." → on confirm, call `instapaperProvider.delete(bookmarkId)` → remove from list + clear cached article.
- **Acceptance criteria**:
  - [ ] Swipe left → archive API call + removed from list
  - [ ] Archive shows "Archived" notification with Undo
  - [ ] Undo calls unarchive API + re-adds to list
  - [ ] Swipe right → confirmation dialog
  - [ ] Confirm delete → delete API call + clear cache + removed from list
  - [ ] Cancel delete → no action
  - [ ] Uses design system tokens for action button colors
  - [ ] `dart analyze` reports 0 issues
- **Principles**: DP4
- **Effort**: M (~45 min)
- **Depends on**: TASK-310, TASK-314

---

## Sprint 7: Settings & Polish

### TASK-318: Settings — Connected Services section
- **Priority**: 5
- **Files**: `MODIFY: lib/screens/settings_screen.dart`
- **Action**: Add "Connected Services" section. When connected: show "Instapaper — Connected ✓" + [Disconnect] button + `archiveOnFinish` toggle + `showArchivedArticles` toggle. When disconnected: show "Instapaper — Not connected" + [Connect] button that opens `InstapaperLoginModal`. Disconnect calls `InstapaperAuth.disconnect()`. Toggle states from AppConfig.
- **Acceptance criteria**:
  - [ ] "Connected Services" section visible
  - [ ] Connected state shows status + Disconnect button + toggles
  - [ ] Disconnected state shows status + Connect button
  - [ ] Connect opens `InstapaperLoginModal`
  - [ ] Disconnect calls `InstapaperAuth.disconnect()`
  - [ ] `archiveOnFinish` toggle reads/writes AppConfig
  - [ ] `showArchivedArticles` toggle reads/writes AppConfig
  - [ ] Shell surface tokens only (Rule 7)
  - [ ] `dart analyze` reports 0 issues
- **Principles**: DP3, DP4
- **Effort**: M (~1 hr)
- **Depends on**: TASK-303, TASK-319

---

## Sprint 8: Integration Tests & Final Verification

### TASK-320: Integration test — connect + fetch + read flow
- **Priority**: Integration
- **Files**: `CREATE: integration_test/instapaper_flow_test.dart`
- **Action**: Mock all HTTP calls. Flow: connect → fetch bookmarks → verify library section appears → tap article → reading viewport → pause → verify progress sync → finish → verify archive prompt.
- **Acceptance criteria**:
  - [ ] Auth mock returns valid tokens
  - [ ] Bookmark list mock returns 3 articles
  - [ ] Library section renders with 3 article cards
  - [ ] Article tap navigates to reading viewport with correct words
  - [ ] Pause triggers progress sync mock call
  - [ ] Finish triggers archive mock call (when `archiveOnFinish` enabled)
  - [ ] All assertions pass
- **Principles**: DP5
- **Effort**: L (~2 hr)
- **Depends on**: TASK-316

### TASK-321: Offline reading test
- **Priority**: Integration
- **Files**: `CREATE: test/services/instapaper_cache_test.dart` (extend TASK-308D)
- **Action**: Cache bookmarks + article text → simulate no network → verify cached articles readable → verify library shows cached list.
- **Acceptance criteria**:
  - [ ] Cached bookmarks load without network
  - [ ] Cached article text available for reading without network
  - [ ] Library section renders from cache
  - [ ] All tests pass
- **Principles**: DP2
- **Effort**: S (~30 min)
- **Depends on**: TASK-306, TASK-314

### TASK-322: Library section widget tests
- **Priority**: Integration
- **Files**: `CREATE: test/widgets/library_section_test.dart`, `CREATE: test/widgets/article_card_test.dart`
- **Action**: Test: sections visible when source connected, hidden when not. Article cards render title + domain + progress. Collapse/expand works. Swipe actions trigger callbacks.
- **Acceptance criteria**:
  - [ ] Section rendered when children provided
  - [ ] Section NOT rendered when children empty
  - [ ] Collapse/expand toggles content visibility
  - [ ] Article card renders title, domain, word count
  - [ ] Article card progress bar visible only when > 0
  - [ ] All tests pass
- **Principles**: DP4
- **Effort**: S (~30 min)
- **Depends on**: TASK-309, TASK-310

### TASK-323: `dart analyze` + `flutter test` clean sweep
- **Priority**: Final gate
- **Files**: All
- **Action**: `dart analyze lib/` → zero issues. `flutter test` → all existing + new tests pass. `flutter test integration_test/` → all pass on device.
- **Acceptance criteria**:
  - [ ] `dart analyze lib/` → 0 issues
  - [ ] `flutter test` → 0 failures (excluding pre-existing dynamic_font_size skips)
  - [ ] `flutter test integration_test/` → all pass
  - [ ] No regressions in existing functionality
- **Principles**: All
- **Effort**: S (~30 min)
- **Depends on**: All

---

## Dependency Graph

```
TASK-300 (deps) ──┬── TASK-302 (secure storage) ──┬── TASK-303 (auth) ──┬── TASK-304 (service)
                  │                                 │                     │
                  │                                 └── TASK-305 (instaparser)
                  └── TASK-307 (html extractor)                          │
                                                                         │
TASK-301 (model) ──┬── TASK-304                                          │
                   ├── TASK-306 (cache) ─── TASK-314 (provider) ─── TASK-315B (wire to reader)
                   ├── TASK-310 (card)                                    │
                   └── TASK-315A (route)                            TASK-316 (sync)
                                                                         │
TASK-309 (section widget) ─┬── TASK-313 (library redesign) ─── TASK-317 (swipe actions)
TASK-311 (add sheet) ──────┘
TASK-312 (login modal) ── TASK-303

TASK-319 (AppConfig) ──┬── TASK-303
                       └── TASK-318 (settings)

TASK-308A ── TASK-301
TASK-308B ── TASK-307
TASK-308C ── TASK-303, TASK-304
TASK-308D ── TASK-306

TASK-320 ── TASK-316
TASK-321 ── TASK-306, TASK-314
TASK-322 ── TASK-309, TASK-310
TASK-323 ── All
```

## Effort Distribution

| Size | Count | Tasks |
|---|---|---|
| XS (~15 min) | 3 | TASK-300, TASK-302, TASK-315A |
| S (~20–30 min) | 9 | TASK-301, TASK-305, TASK-307, TASK-308A, TASK-308B, TASK-308D, TASK-309, TASK-311, TASK-319, TASK-321, TASK-322, TASK-323 |
| M (~45 min–1.5 hr) | 9 | TASK-303, TASK-306, TASK-308C, TASK-310, TASK-312, TASK-314, TASK-315B, TASK-316, TASK-317, TASK-318 |
| L (~2–2.5 hr) | 2 | TASK-304, TASK-313, TASK-320 |
| **Total** | **24 tasks** | **~22 hours estimated** |
