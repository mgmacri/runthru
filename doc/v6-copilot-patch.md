# Speedy Boy — Copilot Instructions v6 Patch

Apply these changes to `.github/copilot-instructions.md` on top of the existing v4 content.
v5 was a removal release (no new rules).

---

## New Rules (29–34)

29. **Instapaper credentials never in source control.** Consumer key/secret passed via `--dart-define` at build time or loaded from `String.fromEnvironment`. OAuth user tokens stored ONLY in `flutter_secure_storage`. Never log tokens. User email/password used once for xAuth exchange, then immediately discarded — never stored in state, config, SharedPreferences, or logs.

30. **Article text is always cached after first fetch.** After first successful extraction (via `get_text` or Instaparser), cache locally in `<appSupport>/instapaper_cache/articles/<bookmarkId>.json`. Never re-download unless user explicitly refreshes the article. Offline reading of cached articles must work without network.

31. **Prefer `get_text` over Instaparser.** The Instapaper Full API's `bookmarks/get_text` endpoint is free and returns pre-parsed HTML. Only fall back to Instaparser when `get_text` fails or returns empty content. This preserves the user's Instaparser credit budget (free tier: 1,000/month).

32. **Library sections are source-driven.** Each connected service gets a collapsible section in the library. Sections only appear when the source is connected and has content. No empty placeholder sections. No "Connect X" banners in the main library list. Connection management lives in the [+] sheet and Settings.

33. **Progress sync is fire-and-forget.** `InstapaperService.updateReadProgress()` is called on pause/finish but never awaited in gesture handlers. Failures are silently logged. Never block UI for progress sync.

34. **Instapaper articles use the same reading engine.** Articles enter `ParallaxReadingScreen` via the `instapaperBookmark` parameter, same pattern as `clipboardDocument`. All RSVP, ContextReveal, gesture, WPM dial, and hint features work identically. No separate reading path.

---

## New Design System Files (v6)

```
lib/services/instapaper_auth.dart       → InstapaperAuth (xAuth + token management)
lib/services/instapaper_service.dart    → InstapaperService (bookmark CRUD + sync)
lib/services/instapaper_cache.dart      → InstapaperCache (offline article storage)
lib/services/instaparser_service.dart   → InstaparserService (fallback article extraction)
lib/services/secure_storage.dart        → SecureStorageService (flutter_secure_storage wrapper)
lib/models/instapaper_bookmark.dart     → InstapaperBookmark model
lib/core/html_text_extractor.dart       → HtmlTextExtractor (HTML → plain text → words)
lib/widgets/library_section.dart        → LibrarySection (collapsible section container)
lib/widgets/article_card.dart           → ArticleCard (Instapaper bookmark card)
lib/widgets/source_add_sheet.dart       → SourceAddSheet ([+] bottom sheet)
lib/widgets/instapaper_login_modal.dart → InstapaperLoginModal (email/password → xAuth)
lib/providers/instapaper_provider.dart  → instapaperBookmarksProvider (Riverpod)
```

---

## New AppConfig Fields (v6)

```dart
final bool instapaperConnected;       // default: false
final bool archiveOnFinish;           // default: false
final bool showArchivedArticles;      // default: false
```

### New ConfigNotifier Methods

```dart
Future<void> setInstapaperConnected(bool connected);
Future<void> setArchiveOnFinish(bool archive);
Future<void> setShowArchivedArticles(bool show);
```

---

## Updated Route Map (v6)

| Route | Screen | Params |
|---|---|---|
| `/` | HomeShell (library) | `?tab=N` |
| `/read` | ParallaxReadingScreen | `filePath` (PDF) |
| `/read-legacy` | ReadingScreen | `filePath` |
| `/read-clipboard` | ParallaxReadingScreen | `extra: ClipboardDocument` |
| `/read-instapaper` | ParallaxReadingScreen | `extra: InstapaperBookmark` | **NEW** |
| `/range-picker` | RangePickerScreen | `filePath` |
| `/settings` | `/?tab=3` redirect | — |

---

## Updated Skill Mapping (v6 additions)

| Domain | Skill File | v6 Tasks |
|---|---|---|
| HTTP/networking | `flutter-handling-http-and-json` | OAuth signing, API calls, JSON parsing |
| Secure storage | `flutter-working-with-databases` | flutter_secure_storage for tokens |
| State management | `riverpod-providers` | Bookmark list provider, auth state |
| Layout | `flutter-building-layouts` | Sectioned library, article cards, source sheet |
| Forms | `flutter-building-forms` | Login modal (email/password) |
| Concurrency | `flutter-handling-concurrency` | Background sync, cache I/O in Isolates |
| Caching | `flutter-caching-data` | Article text caching, bookmark list caching |
| Testing | `flutter-testing-apps` + `riverpod-testing` | All test files |
| Navigation | `flutter-implementing-navigation-and-routing` | `/read-instapaper` route |
| Accessibility | `flutter-improving-accessibility` | Article card semantics, section headers |
