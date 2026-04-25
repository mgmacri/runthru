# Speedy Boy v6.0 — Instapaper Integration Design Specification

**Product**: Speed-reading app with 3D neumorphic viewport — adding Instapaper as a content source
**Spec Version**: 6.0.0
**Date**: 2026-04-06
**Supersedes**: v5-design-spec.md (removal release)
**Platform**: Flutter (Dart) — Android, iOS, Windows, macOS, Linux, Web
**Primary Test Device**: Android emulator (Pixel-class, 412×892 @2.6x)

This document is a **v6 additive specification**. It incorporates all v4 content by reference (v5 was a removal release with no behavioral changes) and specifies all new components, modified components, and integration points for Instapaper article reading.

---

## Change Log

| Version | Date | Summary |
|---|---|---|
| 6.0.0 | 2026-04-06 | Instapaper integration: sectioned library, article reading, bidirectional progress sync |

### v6 Change Summary

| Change | Type | Priority | Complexity | Source |
|---|---|---|---|---|
| Library sectioned layout | Modified component | High | L | User request |
| Instapaper auth (xAuth OAuth 1.0a) | New component | High | M | Instapaper API docs |
| Instapaper bookmark service | New component | High | L | Instapaper API docs |
| Instaparser fallback extractor | New component | Medium | S | Instaparser API docs |
| Article card widget | New component | High | M | User request |
| Source add bottom sheet | New component | Medium | S | User request |
| Instapaper login modal | New component | Medium | M | User request |
| HTML-to-text extraction | New component | High | S | Integration requirement |
| Reading progress sync | New behavior | High | M | User request |
| Archive/delete from library | New behavior | Medium | M | User request |
| Settings — Connected Services | Modified component | Low | S | User request |
| AppConfig — Instapaper fields | Modified component | High | XS | Foundation |
| Instapaper bookmark cache | New component | Medium | M | Offline requirement |

---

## Design Principles

This version uses lightweight rationale (not evidence-graded) since the integration is API-driven infrastructure rather than cognitive/UX research territory.

### DP1: Free API First

**Statement**: Always try the Instapaper Full API (`bookmarks/get_text`) before consuming Instaparser credits. The Full API is free and the text is already parsed by Instapaper's pipeline.

**Rationale**: Instaparser free tier is 1,000 credits/month. A heavy reader could exhaust that in days. The Full API has no per-request cost.

### DP2: Offline Resilience

**Statement**: After first fetch, article text is cached locally. Opening the library and reading cached articles must work without network. Only sync operations (progress write-back, bookmark list refresh) require connectivity.

**Rationale**: Reading happens everywhere — planes, subways, Wi-Fi dead zones. Cached content must be self-sufficient.

### DP3: Credential Hygiene

**Statement**: User email/password are used once for xAuth token exchange, then immediately discarded. OAuth tokens live only in platform-encrypted secure storage. Consumer key/secret are compile-time constants never committed to source control.

**Rationale**: OWASP credential management best practices. No credential material in logs, state, or persistent storage beyond flutter_secure_storage.

### DP4: Source-Driven Sections

**Statement**: The library screen shows sections only for connected sources that have content. No empty placeholder sections. No "Connect Instapaper" banner polluting the library when the user hasn't opted in.

**Rationale**: Clean default experience. Instapaper is opt-in. The library starts identical to v5 until the user explicitly connects a source.

### DP5: Same Reading Experience

**Statement**: Instapaper articles enter the exact same RSVP reading viewport as PDFs and clipboard documents. All existing features (gestures, ContextReveal, WPM dial, hints, sentence view) work identically. No feature gaps between content sources.

**Rationale**: One reading engine, one set of muscle memory. Content source is an input detail, not a UX fork.

---

## New Components

### Component: InstapaperAuth

---
**Version**: 1
**Design principle**: DP3 (Credential Hygiene)

---

#### Purpose

Manages OAuth 1.0a authentication with the Instapaper Full API using the xAuth extension. Converts a one-time email/password entry into long-lived OAuth tokens stored in platform-encrypted secure storage.

**When to use**: User connecting their Instapaper account for the first time, or re-authenticating after token expiry.
**When NOT to use**: Any subsequent API call (those use stored tokens via InstapaperService).

#### States

| State | Description | Trigger |
|---|---|---|
| `disconnected` | No OAuth tokens in secure storage | Default / user disconnects |
| `authenticating` | xAuth request in flight | User submits credentials |
| `connected` | Valid OAuth tokens stored | Successful xAuth exchange |
| `error` | Auth failed (bad credentials, network) | xAuth returns 401/network error |

#### Behavior

1. `authenticate(email, password)` sends `POST /api/1/oauth/access_token` with OAuth 1.0a signature and xAuth parameters (`x_auth_username`, `x_auth_password`, `x_auth_mode=client_auth`).
2. On success, stores `oauth_token` and `oauth_token_secret` in `flutter_secure_storage`.
3. Email and password are **immediately discarded** — never stored in memory beyond the method scope.
4. `verifyCredentials()` calls `POST /api/1/account/verify_credentials` to confirm tokens are still valid. Returns user info (username, subscription type).
5. `disconnect()` deletes OAuth tokens from secure storage and clears cached bookmark data.
6. `isConnected` checks whether tokens exist in secure storage (synchronous or cached check).
7. Consumer key and consumer secret come from `String.fromEnvironment('INSTAPAPER_KEY')` and `String.fromEnvironment('INSTAPAPER_SECRET')` — compile-time only, never in source.

#### Tokens Consumed

| Token | Usage |
|---|---|
| `shellBase` | Login modal background |
| `shellTextPrimary` | Field labels |
| `shellAccent` | Connect button |
| `shellError` | Error message text |

#### Security Constraints

- NEVER store email or password anywhere (memory, SharedPreferences, logs).
- NEVER log OAuth tokens or consumer credentials.
- Consumer key/secret via `--dart-define` or `.env` excluded from git.
- OAuth tokens stored ONLY in `flutter_secure_storage`.

#### Do / Don't

| Do | Don't | Why |
|---|---|---|
| Discard credentials immediately after xAuth | Store email/password in state, config, or logs | DP3 |
| Use `String.fromEnvironment` for consumer key/secret | Hardcode consumer key/secret in source | DP3 |
| Store OAuth tokens in flutter_secure_storage | Store tokens in SharedPreferences or plain files | DP3 |
| Handle 401 with re-auth prompt | Silently retry with potentially expired tokens | Prevents infinite retry loops |

---

### Component: InstapaperService

---
**Version**: 1
**Design principle**: DP1 (Free API First), DP2 (Offline Resilience)

---

#### Purpose

API client for all Instapaper Full API operations: listing bookmarks, fetching article text, syncing reading progress, archiving, and deleting. All requests are OAuth 1.0a signed using stored tokens.

**When to use**: Any data exchange with the Instapaper API.
**When NOT to use**: Article text extraction (that's InstaparserService as fallback).

#### API Endpoints

| Endpoint | Method | Purpose |
|---|---|---|
| `/api/1/bookmarks/list` | POST | List unread bookmarks (max 500) |
| `/api/1/bookmarks/get_text` | POST | Get pre-parsed article HTML |
| `/api/1/bookmarks/update_read_progress` | POST | Sync reading position (0.0–1.0) |
| `/api/1/bookmarks/archive` | POST | Archive a bookmark |
| `/api/1/bookmarks/unarchive` | POST | Undo archive |
| `/api/1/bookmarks/delete` | POST | Permanently delete |
| `/api/1/account/verify_credentials` | POST | Verify auth tokens |

#### Behavior

1. All requests signed with OAuth 1.0a using stored `oauth_token` + `oauth_token_secret` and compile-time `consumer_key` + `consumer_secret`.
2. HTTP 401 → tokens expired → set auth state to `disconnected`, prompt re-auth.
3. HTTP 429 or 5xx → exponential backoff (1s, 2s, 4s, max 3 retries).
4. Network unreachable → return cached data if available, surface "offline" indicator.
5. `listBookmarks` returns up to 500 items per the API limit. If exactly 500 returned, show a note: "Showing 500 most recent articles".
6. `getArticleText(bookmarkId)` returns raw HTML. Caller must strip tags via `HtmlTextExtractor`.
7. `updateReadProgress(bookmarkId, progress)` is fire-and-forget — no await in UI gesture handlers. Failures are silently logged.

#### Error Handling

| Error | Response | User Impact |
|---|---|---|
| 401 Unauthorized | Clear tokens, prompt re-auth | "Session expired. Please reconnect." |
| 429 Rate Limited | Exponential backoff, max 3 retries | "Too many requests. Try again shortly." |
| Network unreachable | Return cached data | "Offline — showing cached articles" |
| 500+ Server Error | Retry once after 2s, then surface error | "Instapaper is temporarily unavailable" |

#### Do / Don't

| Do | Don't | Why |
|---|---|---|
| Sign every request with OAuth 1.0a | Send raw requests without auth | API requires it |
| Handle 401 with re-auth flow | Silently retry with expired tokens | DP3 |
| Return cached data when offline | Throw on network error | DP2 |
| Fire-and-forget progress sync | Await progress sync in gesture handler | UI responsiveness |
| Handle the 500-bookmark API limit gracefully | Assume unlimited bookmarks | Known API limitation |

---

### Component: InstaparserService

---
**Version**: 1
**Design principle**: DP1 (Free API First)

---

#### Purpose

Fallback article text extraction via the Instaparser API. Only used when Instapaper's own `get_text` fails or returns empty content.

**When to use**: Article text extraction when `InstapaperService.getArticleText()` fails.
**When NOT to use**: As the primary extraction path (wastes credits).

#### Behavior

1. `extractArticle(url)` sends `POST https://instaparser.com/api/1/article` with Bearer token and URL in JSON body.
2. Returns `InstaparserArticle(title, content, wordCount)` on success, `null` on failure.
3. Bearer token retrieved from `flutter_secure_storage` (set during Instaparser key configuration in Settings).
4. Result is cached immediately — never re-fetched for the same URL.

#### Do / Don't

| Do | Don't | Why |
|---|---|---|
| Only call after `get_text` fails | Call for every article | DP1 — preserves free tier credits |
| Cache result after first successful extraction | Re-extract on every read | DP2 |
| Handle 402 (out of credits) gracefully | Crash on credit exhaustion | User experience |

---

### Component: HtmlTextExtractor

---
**Version**: 1
**Design principle**: DP5 (Same Reading Experience)

---

#### Purpose

Converts HTML article content (from `get_text` or Instaparser) into clean plain text suitable for the RSVP word tokenizer. Same pipeline as PDF and clipboard text.

**When to use**: Processing any HTML content before feeding to the reading engine.
**When NOT to use**: Content that's already plain text (clipboard).

#### Behavior

1. `htmlToPlainText(String html)` strips all HTML tags, preserves `<p>`, `<br>`, `<h*>` as paragraph breaks (`\n\n`), decodes HTML entities (`&amp;` → `&`, `&nbsp;` → space, etc.), collapses multiple whitespace, trims.
2. `htmlToWords(String html)` calls `htmlToPlainText` then tokenizes using the same sentence-splitting pipeline as `ClipboardDocument._textToSentences()` and `ExtractedDocument`.
3. Output is a `List<Sentence>` compatible with the existing reading engine.
4. Heavy processing runs in `Isolate.run()` (Rule 11).

#### Do / Don't

| Do | Don't | Why |
|---|---|---|
| Preserve paragraph breaks as sentence boundaries | Collapse all whitespace into single spaces | Sentence structure matters for ContextReveal |
| Decode all HTML entities | Pass raw entities to the tokenizer | `&amp;` would appear as a "word" |
| Run in Isolate | Parse HTML on the main thread | Rule 11 |
| Reuse the existing sentence-splitting pipeline | Create a separate tokenizer | DP5 — consistency |

---

### Component: InstapaperCache

---
**Version**: 1
**Design principle**: DP2 (Offline Resilience)

---

#### Purpose

Local cache for Instapaper bookmark metadata and extracted article text. Enables offline reading of previously-fetched articles and fast library loading without network.

**When to use**: Storing and retrieving bookmark data and article text.
**When NOT to use**: Storing OAuth tokens (use secure_storage).

#### Behavior

1. Bookmark list cached as JSON in app documents directory (`<appSupport>/instapaper_cache/bookmarks.json`).
2. Article text cached per bookmark: `<appSupport>/instapaper_cache/articles/<bookmarkId>.json` containing `{text, words, wordCount, fetchedAt}`.
3. On library refresh: fetch remote list → merge with cache (remote wins for changed fields, cache retains `cachedText`).
4. `clearCache()` deletes entire `instapaper_cache/` directory — called on disconnect.
5. All file I/O runs in `Isolate.run()` (Rule 11).

#### Do / Don't

| Do | Don't | Why |
|---|---|---|
| Cache bookmark list and article text separately | Bundle everything in one giant file | Individual article caching enables incremental fetches |
| Run all file I/O in Isolates | Use synchronous file operations | Rule 11 |
| Clear cache on disconnect | Leave orphaned cache files | DP3 — clean disconnect |
| Merge remote + cache on refresh | Overwrite cache blindly | Preserves cached article text during list refresh |

---

### Component: InstapaperBookmark (Model)

---
**Version**: 1

---

#### Purpose

Data model representing a single Instapaper bookmark with both API-sourced and locally-computed fields.

#### Fields

| Field | Type | Source | Notes |
|---|---|---|---|
| `bookmarkId` | `int` | API | Instapaper's unique ID |
| `title` | `String` | API | Article title |
| `url` | `String` | API | Original article URL |
| `description` | `String?` | API | Optional excerpt |
| `progress` | `double` | API | 0.0–1.0 reading progress |
| `progressTimestamp` | `int` | API | Unix timestamp of last progress update |
| `savedAt` | `DateTime` | API | When bookmark was saved |
| `starred` | `bool` | API | Whether bookmark is starred |
| `domain` | `String?` | Computed | Extracted from URL (`Uri.parse(url).host`) |
| `cachedText` | `String?` | Local | Extracted article plain text |
| `wordCount` | `int?` | Local | Word count from extracted text |
| `words` | `List<String>?` | Local | Tokenized word list for RSVP |

#### Methods

```dart
factory InstapaperBookmark.fromJson(Map<String, dynamic> json);
Map<String, dynamic> toJson();
InstapaperBookmark copyWith({...});

// Progress mapping
static double wordIndexToProgress(int wordIndex, int totalWords) =>
    totalWords > 0 ? wordIndex / totalWords : 0.0;

static int progressToWordIndex(double progress, int totalWords) =>
    (progress * totalWords).round().clamp(0, totalWords - 1);
```

---

### Component: SecureStorageService

---
**Version**: 1
**Design principle**: DP3 (Credential Hygiene)

---

#### Purpose

Thin wrapper around `flutter_secure_storage` providing typed methods for all credential storage operations. Single point of access for OAuth tokens and API keys.

#### Methods

| Method | Purpose |
|---|---|
| `saveOAuthTokens(String token, String secret)` | Store Instapaper OAuth credentials |
| `getOAuthTokens()` → `(String, String)?` | Retrieve OAuth token pair |
| `deleteOAuthTokens()` | Clear on disconnect |
| `saveInstaparserKey(String key)` | Store Instaparser Bearer token |
| `getInstaparserKey()` → `String?` | Retrieve Instaparser key |
| `deleteInstaparserKey()` | Clear Instaparser credentials |

#### Do / Don't

| Do | Don't | Why |
|---|---|---|
| Use flutter_secure_storage for all secrets | Store secrets in SharedPreferences | Platform-encrypted storage |
| Return nullable types for missing keys | Throw on missing keys | Graceful disconnected state |
| Delete tokens immediately on disconnect | Defer deletion | DP3 |

---

### Component: ArticleCard

---
**Version**: 1
**Design principle**: DP4 (Source-Driven Sections)

---

#### Purpose

Card widget displaying an Instapaper bookmark in the library's Instapaper section. Shows article metadata and reading progress.

**When to use**: Instapaper section of the library screen.
**When NOT to use**: Local PDF entries (those use existing PdfCard).

#### Anatomy

```
┌─────────────────────────────────────┐
│ Article Title                        │
│ example.com · 1,847 words           │
│ ████████░░░░░░░░░░░░  42%          │
└─────────────────────────────────────┘
```

- **Title**: `SpeedyBoyTypography.shellBody` weight `semiBold`, max 2 lines, overflow ellipsis.
- **Subtitle**: Domain + word count, `SpeedyBoyTypography.shellCaption`, `shellTextSecondary`.
- **Progress bar**: Thin horizontal bar using `shellAccent` fill, `shellBase` track. Only shown when progress > 0.
- **Surface**: `SpeedyBoyDecorations.raisedDecoration(SpeedyBoyTokens.shellBase, NeumorphicSize.medium)`.

#### States

| State | Visual | Trigger |
|---|---|---|
| `default` | Card with metadata | Normal display |
| `loading` | Neumorphic pulse overlay | Article text being fetched |
| `swiped` | Reveal archive/delete buttons | Horizontal swipe on card |

#### Interaction

| Event | Response | Timing |
|---|---|---|
| Tap | Fetch article text → navigate to reading viewport | Immediate (loading state until text ready) |
| Swipe left | Reveal amber Archive button + red Delete button | 200ms slide |
| Long-press | Context menu: Archive, Delete, Open in Browser | 500ms hold |

#### Accessibility

- **Screen reader**: `Semantics(label: "$title from $domain, $progress percent read")`
- **Keyboard**: Enter to open, Delete key for context menu
- **Swipe actions**: Labeled `Semantics(label: "Archive")` and `Semantics(label: "Delete")`

#### Do / Don't

| Do | Don't | Why |
|---|---|---|
| Use `SpeedyBoyDecorations.raisedDecoration` | Hardcode BoxDecoration or shadows | Rule 3 |
| Use `shellTextPrimary` / `shellTextSecondary` | Use `stageText` or raw Colors | Rule 7 — shell surface |
| Show domain extracted from URL | Show raw URL | Readability |
| Show progress bar only when > 0 | Always show empty progress bar | Clean default state |
| Show neumorphic pulse during loading | Use CircularProgressIndicator | Rule 15 |

---

### Component: LibrarySection

---
**Version**: 1
**Design principle**: DP4 (Source-Driven Sections)

---

#### Purpose

Reusable collapsible section container for the library screen. Groups content from a single source (Instapaper articles, local files) under a header.

#### Anatomy

```
  SECTION TITLE                    [action]
  ┌─────────────────────────────────────┐
  │ Child item 1                        │
  ├─────────────────────────────────────┤
  │ Child item 2                        │
  └─────────────────────────────────────┘
```

- **Header**: Uppercase section title in `SpeedyBoyTypography.shellCaption` weight `semiBold` with `shellTextSecondary`. Optional trailing action widget (e.g., refresh button).
- **Body**: Vertically stacked children with 8px spacing.
- **Collapse**: Tap header to toggle. Animated height with 200ms ease-in-out. Collapse state is ephemeral (in-memory, resets on screen rebuild).

#### Behavior

1. Section only renders if it has children (no empty sections — DP4).
2. Default state: expanded.
3. Collapse animation: 200ms, Curves.easeInOut. Reduced motion: instant toggle (Rule 5).

#### Tokens Consumed

| Token | Usage |
|---|---|
| `shellTextSecondary` | Section header text |
| `shellBase` | Background (inherits from parent) |

#### Do / Don't

| Do | Don't | Why |
|---|---|---|
| Hide sections with no content | Show empty section with placeholder text | DP4 |
| Use ephemeral collapse state | Persist collapse state to AppConfig | Over-engineering |
| Animate collapse with reduced motion check | Skip reduced motion check | Rule 5 |

---

### Component: SourceAddSheet

---
**Version**: 1
**Design principle**: DP4 (Source-Driven Sections)

---

#### Purpose

Bottom sheet for adding or connecting content sources. Triggered by the [+] button in the library app bar.

#### Anatomy

```
┌─────────────────────────────────────┐
│  Add Content                         │
│                                      │
│  ▶ Connect Instapaper               │
│  ▶ Browse Local Files               │
│  ▶ Paste from Clipboard             │
└─────────────────────────────────────┘
```

- Each option is a tappable row with icon + label.
- "Connect Instapaper" only shown when NOT connected. When connected, shows "Instapaper Connected ✓" (non-tappable).
- "Browse Local Files" reuses existing folder picker flow.
- "Paste from Clipboard" reuses existing clipboard flow.

#### Behavior

1. Tapping "Connect Instapaper" opens the `InstapaperLoginModal`.
2. Tapping "Browse Local Files" calls `FilePicker.platform.pickFiles()` (existing flow).
3. Tapping "Paste from Clipboard" calls `ClipboardService.readFromClipboard()` (existing flow).
4. Sheet auto-dismisses after source action completes.

#### Tokens Consumed

| Token | Usage |
|---|---|
| `shellBase` | Sheet background |
| `shellTextPrimary` | Option labels |
| `shellAccent` | Icon tint |

#### Do / Don't

| Do | Don't | Why |
|---|---|---|
| Show "Connect Instapaper" only when disconnected | Always show connect option | Avoid confusion when already connected |
| Dismiss sheet after action | Leave sheet open | Natural flow |
| Design for future sources (Pocket, RSS) | Hard-code exactly 3 options | Extensibility |

---

### Component: InstapaperLoginModal

---
**Version**: 1
**Design principle**: DP3 (Credential Hygiene)

---

#### Purpose

Modal dialog for entering Instapaper email and password. Credentials are used once for xAuth token exchange, then discarded.

#### Anatomy

```
┌─────────────────────────────────────┐
│  Connect Instapaper                  │
│                                      │
│  Email                               │
│  ┌─────────────────────────────┐    │
│  │ user@example.com            │    │
│  └─────────────────────────────┘    │
│                                      │
│  Password                            │
│  ┌─────────────────────────────┐    │
│  │ ••••••••                    │    │
│  └─────────────────────────────┘    │
│                                      │
│  [Invalid email or password]         │  ← only shown on error
│                                      │
│        [Cancel]  [Connect]           │
└─────────────────────────────────────┘
```

#### States

| State | Visual | Trigger |
|---|---|---|
| `idle` | Empty fields, Connect enabled | Default |
| `connecting` | Neumorphic pulse on Connect button | Submit |
| `error` | Error message below fields, fields editable | Auth failure |
| `success` | Auto-dismiss modal | Successful auth |

#### Behavior

1. Both fields required — Connect button disabled until both non-empty.
2. Email field: `keyboardType: TextInputType.emailAddress`, `autocorrect: false`.
3. Password field: `obscureText: true`.
4. On Connect: call `InstapaperAuth.authenticate(email, password)`.
5. On success: dismiss modal, Instapaper section appears in library on next rebuild.
6. On error: show inline error message, keep fields populated for retry.
7. On cancel: dismiss modal, no state change.
8. Credentials stored in local `TextEditingController` only — never in state, config, or provider.

#### Accessibility

- **Screen reader**: "Connect Instapaper dialog. Email field. Password field."
- **Keyboard**: Tab between fields, Enter to submit.

#### Do / Don't

| Do | Don't | Why |
|---|---|---|
| Use local TextEditingController only | Store credentials in a Riverpod provider | DP3 |
| Disable Connect until both fields filled | Allow empty submissions | UX |
| Show neumorphic pulse during auth | Show CircularProgressIndicator | Rule 15 |
| Auto-dismiss on success | Require user to manually close | Natural flow |

---

## Modified Components

### Modified: Library Screen — Sectioned Layout

**Change type**: Major refactor

#### Problem

Library screen currently shows a flat list of local PDF files with a clipboard paste button. v6 adds Instapaper as a content source, requiring a sectioned layout with per-source headers.

#### Specification

The library screen becomes a vertically-scrolled list of `LibrarySection` widgets, one per connected content source.

**Section order** (top to bottom):
1. Connected services (Instapaper) — only if connected AND has bookmarks
2. Local Files — existing PDF/EPUB list
3. Clipboard button — always at bottom

**App bar changes**:
- Existing: "Speedy Boy" title + error badge
- Added: [+] button (trailing) → opens `SourceAddSheet`

**Instapaper section header**: "INSTAPAPER" + ↻ refresh button.
- ↻ taps `instapaperProvider.refresh()`.
- Pull-to-refresh on the whole screen also triggers Instapaper refresh.

**Empty states**:
- Instapaper connected, no bookmarks: "No unread articles" text within section.
- Instapaper not connected: section hidden entirely (DP4).
- Local files empty + Instapaper empty: existing empty-state messaging.

#### Constants

| Token | Value | Type | Rationale |
|---|---|---|---|
| Section header font | `SpeedyBoyTypography.shellCaption` | TextStyle | Shell surface, small caps feel |
| Section spacing | `16.0` | double | Consistent with existing card spacing |
| Refresh icon size | `20.0` | double | Proportional to section header |

#### Behavioral Rules

1. Sections only render when source is connected AND has content (exception: connected Instapaper with 0 bookmarks shows "No unread articles").
2. Instapaper section always appears above Local Files.
3. Pull-to-refresh triggers ALL connected source refreshes.
4. [+] button is always visible regardless of connection state.
5. Clipboard button position (bottom) is unchanged.

#### Do / Don't

| Do | Don't | Why |
|---|---|---|
| Hide Instapaper section when disconnected | Show empty "Connect Instapaper" placeholder | DP4 |
| Show ↻ refresh button on Instapaper header | Auto-refresh on timer | User-initiated sync only |
| Preserve existing PDF card behavior | Refactor PDF cards into ArticleCard | Different content types |
| Keep clipboard button at bottom | Move clipboard into a section | Clipboard is ephemeral (Rule 28), not a "source" |

---

### Modified: Settings Screen — Connected Services

**Change type**: New section

#### Specification

Add a "Connected Services" section to the settings screen.

```
CONNECTED SERVICES
┌─────────────────────────────────────┐
│ Instapaper          Connected ✓     │
│ [Disconnect]                        │
│                                     │
│ ☑ Archive articles after finishing  │
│ ☐ Show archived articles           │
└─────────────────────────────────────┘
```

**When Instapaper not connected**: Section shows "Instapaper — Not connected" with a [Connect] button that opens `InstapaperLoginModal`.

**Settings:**
- `archiveOnFinish` toggle (default: false) — when enabled, finishing an article archives it in Instapaper.
- `showArchivedArticles` toggle (default: false) — when enabled, archived articles appear in Instapaper section.
- Disconnect button — calls `InstapaperAuth.disconnect()`, clears cache, hides Instapaper section.

---

### Modified: ParallaxReadingScreen — Instapaper Articles

**Change type**: New content source

#### Specification

The reading screen already supports PDF files and clipboard documents. Instapaper articles are the third source, using the same parameter pattern as clipboard.

**New parameter:**
```dart
class ParallaxReadingScreen extends ConsumerStatefulWidget {
  const ParallaxReadingScreen({
    super.key,
    required this.filePath,
    this.clipboardDocument,
    this.instapaperBookmark,   // NEW — v6
  });

  final String filePath;
  final ClipboardDocument? clipboardDocument;
  final InstapaperBookmark? instapaperBookmark;  // NEW
}
```

**Initialization flow for Instapaper articles:**
1. Check `instapaperBookmark.cachedText` — if available, tokenize directly.
2. If not cached: fetch via `InstapaperService.getArticleText(bookmarkId)`.
3. If `get_text` fails: fallback to `InstaparserService.extractArticle(url)`.
4. Strip HTML via `HtmlTextExtractor.htmlToWords()`.
5. Cache result via `InstapaperCache.cacheArticleText()`.
6. Seek to `InstapaperBookmark.progressToWordIndex(bookmark.progress, words.length)`.

**Progress sync:**
- On pause: compute `wordIndexToProgress(currentIndex, totalWords)` → fire-and-forget `InstapaperService.updateReadProgress()`.
- On finish: if `AppConfig.archiveOnFinish` → call `InstapaperService.archiveBookmark()` → show brief confirmation with 5-second undo.

**Undo archive:**
- Shows a transient banner: "Archived in Instapaper" with [Undo] button.
- Undo calls `InstapaperService.unarchiveBookmark()`.
- Banner auto-dismisses after 5 seconds.

#### Behavioral Rules

1. All existing features work identically: gestures, ContextReveal, WPM dial, hints, sentence view.
2. `_isInstapaper` guard follows same pattern as `_isClipboard`.
3. Progress sync is fire-and-forget — never blocks UI.
4. If article text fetch fails entirely (both get_text and Instaparser), show error and navigate back to library.

#### Do / Don't

| Do | Don't | Why |
|---|---|---|
| Reuse existing word timer and reading engine | Fork a separate reading path for articles | DP5 |
| Seek to synced progress position on open | Always start from beginning | User expects continuity |
| Fire-and-forget progress sync | Await sync in gesture handler | UI responsiveness |
| Show 5s undo for archive-on-finish | Archive without undo option | Reversibility |

---

### Modified: AppConfig — Instapaper Fields

**Change type**: New fields

#### Specification

```dart
// New fields in AppConfig
final bool instapaperConnected;     // default: false
final bool archiveOnFinish;         // default: false
final bool showArchivedArticles;    // default: false
```

**New ConfigNotifier methods:**
```dart
Future<void> setInstapaperConnected(bool connected);
Future<void> setArchiveOnFinish(bool archive);
Future<void> setShowArchivedArticles(bool show);
```

All follow the existing `_synchronized(() async { ... })` pattern. JSON round-trip backward compatible (missing keys → defaults).

---

### Modified: AppRouter — Instapaper Reading Route

**Change type**: New route

#### Specification

```dart
// New route for Instapaper article reading
GoRoute(
  path: '/read-instapaper',
  pageBuilder: (context, state) {
    final bookmark = state.extra as InstapaperBookmark?;
    return wallFoldTransitionPage(
      key: state.pageKey,
      child: ParallaxReadingScreen(
        filePath: 'instapaper://${bookmark?.bookmarkId}',
        instapaperBookmark: bookmark,
      ),
    );
  },
),
```

Uses the same `wallFoldTransitionPage` transition as clipboard reading.

---

## New Dependencies

| Package | Purpose | Notes |
|---|---|---|
| `flutter_secure_storage` | Platform-encrypted credential storage | Android Keystore, iOS Keychain |
| `html_unescape` or `html` | HTML entity decoding + tag stripping | For article text extraction |

**Already available in pubspec**: `http` (for API calls).

**OAuth 1.0a signing**: Implement manually or use a lightweight package. The xAuth flow is a single POST — a full OAuth library may be overkill. Evaluate `oauth1` package vs hand-rolled signing.

---

## Integration Test Scenarios

| Test | Description |
|---|---|
| Connect + fetch | Mock xAuth → list bookmarks → verify library section appears |
| Read article | Tap article → fetch text → reading viewport → verify words displayed |
| Progress sync | Read to 50% → pause → verify updateProgress called with ~0.5 |
| Archive on finish | Read to end → verify archive called → verify undo button |
| Offline reading | Cache articles → disable network → verify articles still readable |
| Disconnect | Disconnect → verify section hidden, cache cleared, tokens deleted |
| Swipe archive | Swipe article left → verify archive API called + removed from list |
| Swipe delete | Swipe article right → confirm dialog → verify delete API called |
