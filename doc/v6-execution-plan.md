# Speedy Boy v6.0 — Execution Plan

**Created**: 2026-04-06
**Tasks**: 24 across 8 sprints, organized into 14 work sessions
**Tools**: VS Code + GitHub Copilot (Chat / Edits modes)
**Codebase**: Post-v5.0 (removal release complete). All v4 features operational. 259 tests passing, 20 skipped, 4 pre-existing failures (dynamic_font_size_test.dart).

---

## Tool Strategy

### When to Use Which Mode

| Mode | Use For | Why |
|------|---------|-----|
| **Chat** | Single-file creation, pure logic, model classes, services, tests | Tight context → precise output |
| **Edits** | Multi-file changes (wiring services into screens, provider + screen + router) | Sees + edits multiple files simultaneously |
| **Manual** | API credential setup, Instapaper account registration, device testing | Human-only tasks |

### How to Reference Skills

Load skills via `#file:` references in Copilot Chat. Maximum 2-3 skill files per prompt.

```
#file:.claude/skills/flutter-handling-http-and-json/SKILL.md
#file:.github/copilot-instructions.md
```

### Context Window Golden Rule

**Maximum per prompt**: 2–3 skill files + target source files + copilot rules.
Every session below specifies exactly what to include.

---

## Skill → Task Cluster Map

```
flutter-handling-http-and-json ─────┬── TASK-303 (auth)
                                    ├── TASK-304 (service)
                                    └── TASK-305 (instaparser)

flutter-working-with-databases ─────┬── TASK-302 (secure storage)
                                    └── TASK-306 (cache)

flutter-handling-concurrency ───────┬── TASK-306 (cache I/O isolates)
                                    ├── TASK-307 (HTML extraction isolate)
                                    └── TASK-315B (article fetch pipeline)

flutter-building-layouts ───────────┬── TASK-309 (section widget)
                                    ├── TASK-310 (article card)
                                    ├── TASK-311 (source add sheet)
                                    └── TASK-313 (library redesign)

flutter-building-forms ─────────────┬── TASK-312 (login modal)
                                    └── TASK-318 (settings toggles)

flutter-animating-apps ─────────────── TASK-309 (collapse animation)

riverpod-providers ─────────────────── TASK-314 (bookmark provider)
riverpod-consumers ─────────────────── TASK-313, TASK-315B (watching providers)
riverpod-auto-dispose ──────────────── TASK-314 (auto-dispose lifecycle)
riverpod-testing ───────────────────── TASK-308C, TASK-320 (provider mocks)

flutter-testing-apps ───────────────── TASK-308A-D, TASK-320-323

flutter-implementing-navigation ────── TASK-315A (route), TASK-313 (nav from library)

flutter-improving-accessibility ────── TASK-310 (card semantics), TASK-309 (section a11y)
```

---

## Sprint 1: Foundation

**Goal**: Install dependencies, create data models, add AppConfig fields.
**Estimated time**: ~1.5 hours

### Session 1.1: Dependencies + Model + Config (S)

**Tasks**: TASK-300, TASK-301, TASK-319
**Mode**: Chat (single-file creation) + Edits (AppConfig modification)
**AI context**:
- Source: `pubspec.yaml`, `lib/store/models.dart`, `lib/store/config.dart`
- Copilot rules: `.github/copilot-instructions.md`
- Spec: `doc/v6-design-spec.md` (InstapaperBookmark model section)

**Prompt sketch**:
```
Execute TASK-300, TASK-301, TASK-319 from doc/v6-task-backlog.md.

#file:pubspec.yaml — Add flutter_secure_storage and html to dependencies.
Run flutter pub get.

#file:lib/store/models.dart — Reference for existing enums and AppConfig structure.
#file:lib/store/config.dart — Reference for setter method pattern.

Create lib/models/instapaper_bookmark.dart per spec: all 12 fields,
fromJson/toJson/copyWith, domain extraction, progress mapping helpers.

Add 3 new AppConfig fields (instapaperConnected, archiveOnFinish,
showArchivedArticles) + 3 setter methods. Follow _synchronized pattern.
JSON backward compatible.

Run dart analyze lib/ after all changes.
```

**Verify**:
- [ ] `flutter pub get` succeeds
- [ ] InstapaperBookmark model compiles
- [ ] AppConfig JSON round-trips with new fields
- [ ] `dart analyze lib/` → 0 issues

---

## Sprint 2: Auth & Services

**Goal**: Build the complete service layer: secure storage, auth, API client, cache, HTML extraction.
**Estimated time**: ~5.5 hours

### Session 2.1: Secure Storage + Auth (M)

**Tasks**: TASK-302, TASK-303
**Mode**: Chat
**AI context**:
- Skills: `flutter-handling-http-and-json`, `flutter-working-with-databases`
- Source: `lib/services/secure_storage.dart` (CREATE), `lib/services/instapaper_auth.dart` (CREATE), `lib/store/config.dart` (reference)
- Copilot rules: `.github/copilot-instructions.md`

**Prompt sketch**:
```
Execute TASK-302 and TASK-303 from doc/v6-task-backlog.md.

#file:.claude/skills/flutter-handling-http-and-json/SKILL.md
#file:.claude/skills/flutter-working-with-databases/SKILL.md

TASK-302: Create lib/services/secure_storage.dart — thin FlutterSecureStorage
wrapper with typed methods for OAuth tokens and Instaparser API key.

TASK-303: Create lib/services/instapaper_auth.dart — xAuth flow.
POST /api/1/oauth/access_token with OAuth 1.0a signature.
Consumer key/secret from String.fromEnvironment only.
Email/password discarded immediately after use (Rule 29).
Store tokens via SecureStorageService.
verifyCredentials(), disconnect(), isConnected.

Reference: Instapaper API uses OAuth 1.0a xAuth extension.
xAuth params: x_auth_username, x_auth_password, x_auth_mode=client_auth

Run dart analyze lib/ after all changes.
```

**Verify**:
- [ ] SecureStorageService compiles with all 6 methods
- [ ] InstapaperAuth compiles with authenticate/verify/disconnect
- [ ] Consumer key from `String.fromEnvironment`
- [ ] No credentials stored beyond method scope
- [ ] `dart analyze` → 0 issues

### Session 2.2: API Client + Instaparser (L)

**Tasks**: TASK-304, TASK-305
**Mode**: Chat
**AI context**:
- Skills: `flutter-handling-http-and-json`, `flutter-handling-concurrency`
- Source: `lib/services/instapaper_service.dart` (CREATE), `lib/services/instaparser_service.dart` (CREATE), `lib/services/secure_storage.dart`, `lib/models/instapaper_bookmark.dart`
- Copilot rules: `.github/copilot-instructions.md`

**Prompt sketch**:
```
Execute TASK-304 and TASK-305 from doc/v6-task-backlog.md.

#file:.claude/skills/flutter-handling-http-and-json/SKILL.md
#file:.claude/skills/flutter-handling-concurrency/SKILL.md
#file:lib/services/secure_storage.dart
#file:lib/models/instapaper_bookmark.dart

TASK-304: Create lib/services/instapaper_service.dart
All requests OAuth 1.0a signed. 6 API methods (list, getText, updateProgress,
archive, unarchive, delete). Handle 401 → disconnect. 429/5xx → backoff.
updateReadProgress is fire-and-forget safe (Rule 33).

TASK-305: Create lib/services/instaparser_service.dart
POST https://instaparser.com/api/1/article with Bearer token.
Returns record of title/content/wordCount. Handle 402 (credits exhausted).

Run dart analyze lib/ after all changes.
```

**Verify**:
- [ ] InstapaperService has all 6 API methods
- [ ] InstaparserService compiles
- [ ] OAuth signing logic correct
- [ ] `dart analyze` → 0 issues

### Session 2.3: HTML Extractor + Cache (M)

**Tasks**: TASK-307, TASK-306
**Mode**: Chat
**AI context**:
- Skills: `flutter-handling-concurrency`, `flutter-caching-data`
- Source: `lib/core/html_text_extractor.dart` (CREATE), `lib/services/instapaper_cache.dart` (CREATE), `lib/core/clipboard_document.dart` (reference for sentence splitting), `lib/services/models.dart` (ExtractedDocument)
- Copilot rules: `.github/copilot-instructions.md`

**Prompt sketch**:
```
Execute TASK-307 and TASK-306 from doc/v6-task-backlog.md.

#file:.claude/skills/flutter-handling-concurrency/SKILL.md
#file:lib/core/clipboard_document.dart — reference for sentence splitting pipeline
#file:lib/services/models.dart — ExtractedDocument, Sentence classes

TASK-307: Create lib/core/html_text_extractor.dart
htmlToPlainText: strip tags, preserve <p>/<br>/<h*> as \n\n, decode entities.
htmlToWords: plaintext → sentences → ExtractedDocument (same pipeline as clipboard).
Run in Isolate.run() (Rule 11).

TASK-306: Create lib/services/instapaper_cache.dart
JSON file cache in <appSupport>/instapaper_cache/.
Bookmark list + per-article text. All I/O in Isolate.run().
Graceful corrupt file handling.

Run dart analyze lib/ after all changes.
```

**Verify**:
- [ ] HTML stripping works for basic tags and entities
- [ ] `htmlToWords` returns `ExtractedDocument` (type check)
- [ ] Cache read/write/clear methods work
- [ ] All heavy I/O in Isolate.run()
- [ ] `dart analyze` → 0 issues

---

## Sprint 3: Service Tests

**Goal**: Unit test all service layer code with mocked HTTP.
**Estimated time**: ~2 hours

### Session 3.1: Model + Extractor Tests (S)

**Tasks**: TASK-308A, TASK-308B
**Mode**: Chat
**AI context**:
- Skills: `flutter-testing-apps`
- Source: `lib/models/instapaper_bookmark.dart`, `lib/core/html_text_extractor.dart`

**Prompt sketch**:
```
Execute TASK-308A and TASK-308B from doc/v6-task-backlog.md.

#file:.claude/skills/flutter-testing-apps/SKILL.md
#file:lib/models/instapaper_bookmark.dart
#file:lib/core/html_text_extractor.dart

TASK-308A: Create test/models/instapaper_bookmark_test.dart
JSON round-trip, copyWith, domain extraction, progress mapping edge cases.

TASK-308B: Create test/core/html_text_extractor_test.dart
Tag stripping, entity decoding, paragraph preservation, empty/malformed input,
script/style removal.

Run flutter test on both files.
```

**Verify**:
- [ ] All model tests pass
- [ ] All HTML extractor tests pass

### Session 3.2: Service + Cache Tests (M)

**Tasks**: TASK-308C, TASK-308D
**Mode**: Chat
**AI context**:
- Skills: `flutter-testing-apps`, `riverpod-testing`
- Source: `lib/services/instapaper_auth.dart`, `lib/services/instapaper_service.dart`, `lib/services/instapaper_cache.dart`

**Prompt sketch**:
```
Execute TASK-308C and TASK-308D from doc/v6-task-backlog.md.

#file:.claude/skills/flutter-testing-apps/SKILL.md
#file:.claude/skills/riverpod-testing/SKILL.md
#file:lib/services/instapaper_auth.dart
#file:lib/services/instapaper_service.dart
#file:lib/services/instapaper_cache.dart

TASK-308C: Create test/services/instapaper_auth_test.dart + instapaper_service_test.dart
Mock HTTP. Test xAuth format, token storage, 401 handling, bookmark parsing, retry.

TASK-308D: Extend test/services/instapaper_cache_test.dart
Cache write/read round-trip, clear, corrupt file, missing directory.

Run flutter test on all test files.
```

**Verify**:
- [ ] All auth tests pass
- [ ] All service tests pass
- [ ] All cache tests pass

---

## Sprint 4: Library UI Widgets

**Goal**: Build reusable UI widgets: section container, article card, source sheet, login modal.
**Estimated time**: ~3 hours

### Session 4.1: Section + Card + Sheet (M)

**Tasks**: TASK-309, TASK-310, TASK-311
**Mode**: Chat (sequential creation)
**AI context**:
- Skills: `flutter-building-layouts`, `flutter-improving-accessibility`
- Source: `lib/design/design.dart`, `lib/design/tokens.dart`, `lib/design/decorations.dart`, `lib/design/typography.dart`
- Copilot rules: `.github/copilot-instructions.md`

**Prompt sketch**:
```
Execute TASK-309, TASK-310, TASK-311 from doc/v6-task-backlog.md.

#file:.claude/skills/flutter-building-layouts/SKILL.md
#file:.claude/skills/flutter-improving-accessibility/SKILL.md
#file:lib/design/tokens.dart — shell surface tokens
#file:lib/design/decorations.dart — raisedDecoration/insetDecoration
#file:lib/design/typography.dart — shellBody, shellCaption

TASK-309: Create lib/widgets/library_section.dart
Collapsible section: header + children. 200ms collapse animation.
Reduced motion check (Rule 5). Shell tokens (Rule 7). Hidden when empty.

TASK-310: Create lib/widgets/article_card.dart
Title (2-line max), domain + word count, progress bar.
raisedDecoration shell. Swipe left reveals archive/delete.
Semantics label. Loading = neumorphic pulse (Rule 15).

TASK-311: Create lib/widgets/source_add_sheet.dart
Bottom sheet: Connect Instapaper / Browse Files / Paste Clipboard.
Conditional on connection state. Shell tokens.

Run dart analyze lib/ after all changes.
```

**Verify**:
- [ ] All 3 widgets compile
- [ ] Shell surface tokens used throughout
- [ ] No hardcoded colors/TextStyle/BoxDecoration
- [ ] `dart analyze` → 0 issues

### Session 4.2: Login Modal (S)

**Tasks**: TASK-312
**Mode**: Chat
**AI context**:
- Skills: `flutter-building-forms`
- Source: `lib/services/instapaper_auth.dart`, `lib/design/tokens.dart`
- Copilot rules: `.github/copilot-instructions.md`

**Prompt sketch**:
```
Execute TASK-312 from doc/v6-task-backlog.md.

#file:.claude/skills/flutter-building-forms/SKILL.md
#file:lib/services/instapaper_auth.dart
#file:lib/design/tokens.dart

Create lib/widgets/instapaper_login_modal.dart
Email + password fields. Connect button disabled until filled.
States: idle, connecting (neumorphic pulse), error (inline), success (auto-dismiss).
Credentials in local TextEditingController only (Rule 29).
Shell surface tokens (Rule 7). No CircularProgressIndicator (Rule 15).

Run dart analyze lib/ after.
```

**Verify**:
- [ ] Modal compiles with all states
- [ ] No credential storage beyond local scope
- [ ] `dart analyze` → 0 issues

---

## Sprint 5: Library Redesign + Provider

**Goal**: Create the Riverpod provider and wire the sectioned library layout.
**Estimated time**: ~3 hours

### Session 5.1: Bookmark Provider (M)

**Tasks**: TASK-314
**Mode**: Chat
**AI context**:
- Skills: `riverpod-providers`, `riverpod-auto-dispose`
- Source: `lib/services/instapaper_service.dart`, `lib/services/instapaper_cache.dart`, `lib/store/config.dart`
- Copilot rules: `.github/copilot-instructions.md`

**Prompt sketch**:
```
Execute TASK-314 from doc/v6-task-backlog.md.

#file:.claude/skills/riverpod-providers/SKILL.md
#file:.claude/skills/riverpod-auto-dispose/SKILL.md
#file:lib/services/instapaper_service.dart
#file:lib/services/instapaper_cache.dart
#file:lib/store/config.dart — reference for existing provider patterns

Create lib/providers/instapaper_provider.dart
Riverpod AsyncNotifier managing bookmark list.
Auto-loads from cache on startup. refresh() fetches remote + merges.
archive(id), delete(id) → API + update local state.
Watches configProvider for instapaperConnected — clears on disconnect.
Auto-dispose.

Run dart analyze lib/ and dart run build_runner build if using @riverpod annotation.
```

**Verify**:
- [ ] Provider compiles
- [ ] Builds from cache on startup
- [ ] refresh/archive/delete methods correct
- [ ] `dart analyze` → 0 issues

### Session 5.2: Library Screen Redesign (L)

**Tasks**: TASK-313
**Mode**: Edits (multi-file integration)
**AI context**:
- Skills: `flutter-building-layouts`, `riverpod-consumers`
- Source: `lib/screens/library_screen.dart`, `lib/widgets/library_section.dart`, `lib/widgets/article_card.dart`, `lib/widgets/source_add_sheet.dart`, `lib/providers/instapaper_provider.dart`
- Copilot rules: `.github/copilot-instructions.md`

**Prompt sketch**:
```
Execute TASK-313 from doc/v6-task-backlog.md.

#file:.claude/skills/flutter-building-layouts/SKILL.md
#file:.claude/skills/riverpod-consumers/SKILL.md
#file:lib/screens/library_screen.dart — MODIFY: refactor into sections
#file:lib/widgets/library_section.dart
#file:lib/widgets/article_card.dart
#file:lib/widgets/source_add_sheet.dart
#file:lib/providers/instapaper_provider.dart

Refactor library_screen.dart into sectioned layout:
1. Instapaper section (if connected + has content) with article cards
2. Local Files section with existing PDF cards
3. Clipboard button at bottom (unchanged)
Add [+] button to app bar → opens SourceAddSheet.
Add ↻ on Instapaper header → refresh provider.
Custom pull-to-refresh (Rule 15 — no RefreshIndicator).
Preserve ALL existing functionality (error badge, clipboard hint, PDF list).

Run dart analyze lib/ after.
```

**Verify**:
- [ ] Library renders Instapaper section when connected
- [ ] Library hides Instapaper section when disconnected
- [ ] PDF list unchanged
- [ ] Clipboard button unchanged
- [ ] [+] button opens source sheet
- [ ] `dart analyze` → 0 issues

---

## Sprint 6: Reading Integration

**Goal**: Wire Instapaper articles into the reading viewport with progress sync.
**Estimated time**: ~2.5 hours

### Session 6.1: Route + Reading Integration (M)

**Tasks**: TASK-315A, TASK-315B
**Mode**: Edits (router + reading screen)
**AI context**:
- Skills: `flutter-implementing-navigation-and-routing`, `riverpod-consumers`
- Source: `lib/navigation/app_router.dart`, `lib/screens/parallax_reading_screen.dart`, `lib/services/instapaper_service.dart`, `lib/services/instaparser_service.dart`, `lib/core/html_text_extractor.dart`, `lib/services/instapaper_cache.dart`
- Copilot rules: `.github/copilot-instructions.md`

**Prompt sketch**:
```
Execute TASK-315A and TASK-315B from doc/v6-task-backlog.md.

#file:.claude/skills/flutter-implementing-navigation-and-routing/SKILL.md
#file:lib/navigation/app_router.dart — ADD /read-instapaper route
#file:lib/screens/parallax_reading_screen.dart — ADD instapaperBookmark param
#file:lib/core/clipboard_document.dart — reference for _isClipboard pattern
#file:lib/services/instapaper_service.dart
#file:lib/core/html_text_extractor.dart

TASK-315A: Add /read-instapaper route using wallFoldTransitionPage.
extra: InstapaperBookmark → filePath: 'instapaper://<bookmarkId>'

TASK-315B: Add instapaperBookmark param to ParallaxReadingScreen.
_isInstapaper guard. Init flow: cached text → get_text → instaparser fallback
→ HTML strip → cache → seek to progress. All existing features unchanged.

Run dart analyze lib/ after.
```

**Verify**:
- [ ] Route `/read-instapaper` works
- [ ] Reading screen accepts InstapaperBookmark
- [ ] Article text extraction pipeline correct
- [ ] Seeks to progress position
- [ ] `dart analyze` → 0 issues

### Session 6.2: Progress Sync + Swipe Actions (M)

**Tasks**: TASK-316, TASK-317
**Mode**: Edits
**AI context**:
- Skills: `flutter-building-layouts`
- Source: `lib/screens/parallax_reading_screen.dart`, `lib/widgets/article_card.dart`, `lib/providers/instapaper_provider.dart`
- Copilot rules: `.github/copilot-instructions.md`

**Prompt sketch**:
```
Execute TASK-316 and TASK-317 from doc/v6-task-backlog.md.

#file:lib/screens/parallax_reading_screen.dart — ADD progress sync
#file:lib/widgets/article_card.dart — WIRE swipe actions
#file:lib/providers/instapaper_provider.dart

TASK-316: On pause → fire-and-forget updateReadProgress (Rule 33).
On finish → if archiveOnFinish → archive + banner with 5s undo.

TASK-317: Wire swipe-left (archive + "Archived" + undo) and
swipe-right (confirm dialog → delete + clear cache).

Run dart analyze lib/ after.
```

**Verify**:
- [ ] Progress syncs on pause (fire-and-forget)
- [ ] Archive-on-finish with undo works
- [ ] Swipe archive/delete wired to API
- [ ] `dart analyze` → 0 issues

---

## Sprint 7: Settings

**Goal**: Add Connected Services section to settings.
**Estimated time**: ~1 hour

### Session 7.1: Settings Integration (M)

**Tasks**: TASK-318
**Mode**: Edits
**AI context**:
- Skills: `flutter-building-forms`
- Source: `lib/screens/settings_screen.dart`, `lib/services/instapaper_auth.dart`, `lib/store/config.dart`
- Copilot rules: `.github/copilot-instructions.md`

**Prompt sketch**:
```
Execute TASK-318 from doc/v6-task-backlog.md.

#file:.claude/skills/flutter-building-forms/SKILL.md
#file:lib/screens/settings_screen.dart — ADD Connected Services section
#file:lib/services/instapaper_auth.dart
#file:lib/store/config.dart

Add "Connected Services" section: connection status, Disconnect button,
archiveOnFinish toggle, showArchivedArticles toggle.
When disconnected: Connect button → opens InstapaperLoginModal.
Shell surface tokens (Rule 7).

Run dart analyze lib/ after.
```

**Verify**:
- [ ] Settings shows Connected Services section
- [ ] Toggles read/write AppConfig
- [ ] Disconnect works
- [ ] `dart analyze` → 0 issues

---

## Sprint 8: Testing & Final Verification

**Goal**: Integration tests, widget tests, clean sweep.
**Estimated time**: ~3.5 hours

### Session 8.1: Widget Tests (S)

**Tasks**: TASK-322
**Mode**: Chat
**AI context**:
- Skills: `flutter-testing-apps`
- Source: `lib/widgets/library_section.dart`, `lib/widgets/article_card.dart`

**Prompt sketch**:
```
Execute TASK-322 from doc/v6-task-backlog.md.

#file:.claude/skills/flutter-testing-apps/SKILL.md
#file:lib/widgets/library_section.dart
#file:lib/widgets/article_card.dart

Create test/widgets/library_section_test.dart and test/widgets/article_card_test.dart.
Test: section visibility, collapse/expand, card rendering, progress bar visibility.

Run flutter test on both files.
```

**Verify**:
- [ ] All widget tests pass

### Session 8.2: Integration Tests (L)

**Tasks**: TASK-320, TASK-321
**Mode**: Chat
**AI context**:
- Skills: `flutter-testing-apps`, `riverpod-testing`
- Source: `lib/providers/instapaper_provider.dart`, `lib/services/instapaper_cache.dart`, integration tests (reference existing: `integration_test/clipboard_test.dart`)

**Prompt sketch**:
```
Execute TASK-320 and TASK-321 from doc/v6-task-backlog.md.

#file:.claude/skills/flutter-testing-apps/SKILL.md
#file:.claude/skills/riverpod-testing/SKILL.md
#file:integration_test/clipboard_test.dart — reference for integration test pattern

TASK-320: Create integration_test/instapaper_flow_test.dart
Mock APIs. Connect → fetch → library section → tap → read → pause → sync → finish → archive.

TASK-321: Extend cache tests for offline reading scenario.
Cache → no network → verify readable.

Run flutter test integration_test/ on device.
```

**Verify**:
- [ ] Integration test passes on device
- [ ] Offline reading test passes

### Session 8.3: Clean Sweep (S)

**Tasks**: TASK-323
**Mode**: Manual
**AI context**: None needed — verification only.

**Steps**:
```bash
dart analyze lib/
flutter test
flutter test integration_test/
```

**Verify**:
- [ ] `dart analyze lib/` → 0 issues
- [ ] `flutter test` → 0 failures (excluding pre-existing dynamic_font_size skips)
- [ ] `flutter test integration_test/` → all pass
- [ ] No regressions in existing functionality

---

## Session Summary Table

| Session | Sprint | Tasks | Mode | Effort | Skills |
|---|---|---|---|---|---|
| 1.1 | 1 | 300, 301, 319 | Chat + Edits | S | — |
| 2.1 | 2 | 302, 303 | Chat | M | http-json, databases |
| 2.2 | 2 | 304, 305 | Chat | L | http-json, concurrency |
| 2.3 | 2 | 307, 306 | Chat | M | concurrency, caching |
| 3.1 | 3 | 308A, 308B | Chat | S | testing |
| 3.2 | 3 | 308C, 308D | Chat | M | testing, riverpod-testing |
| 4.1 | 4 | 309, 310, 311 | Chat | M | layouts, accessibility |
| 4.2 | 4 | 312 | Chat | S | forms |
| 5.1 | 5 | 314 | Chat | M | riverpod-providers, auto-dispose |
| 5.2 | 5 | 313 | Edits | L | layouts, riverpod-consumers |
| 6.1 | 6 | 315A, 315B | Edits | M | navigation, riverpod-consumers |
| 6.2 | 6 | 316, 317 | Edits | M | layouts |
| 7.1 | 7 | 318 | Edits | M | forms |
| 8.1 | 8 | 322 | Chat | S | testing |
| 8.2 | 8 | 320, 321 | Chat | L | testing, riverpod-testing |
| 8.3 | 8 | 323 | Manual | S | — |

**Total sessions**: 16
**Total estimated time**: ~22 hours

---

## Autopilot Prompts

For each sprint, a self-contained prompt is available in the attached spec file (`doc/v6-instapaper-integration.md` — the user's original input) under "Autopilot Prompts". Those prompts can be used directly with Claude Code or similar long-context AI tools for batch execution of entire sprints.

The session-level prompts above are designed for interactive Copilot Chat usage with tighter context budgets.
