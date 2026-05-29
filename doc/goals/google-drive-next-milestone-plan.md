# Google Drive Next Milestone Implementation Plan

## 1. Executive Summary

### What this milestone adds

- Turns the existing Google Drive content-source foundation into a first-class cloud reading workflow: reliable auth restore, optional offline files, stable Drive identities, richer parsing for Docs/PDFs/Slides, source-layout viewing, metadata/TOC extraction, and Drive-aware progress sync.
- Keeps RunThru's core pacing model intact: existing `WordTimerNotifier`, `durationForWord`, ORP utilities, WPM dial, `ContentNormaliser`, PDF/EPUB extractors, go_router, Riverpod, and secure token handling remain the foundation.
- Preserves privacy-by-default: content stays on-device; cloud progress sync is opt-in and must not upload document text.

### Biggest technical risks

- Google Drive progress sync cannot be implemented with strict read-only content scopes alone if RunThru needs to write remote state. The safest Drive-native option is opt-in `appDataFolder`, which requires an additional app-data write scope.
- Google Docs/Slides export quality varies by file type and export MIME. Slides may need runtime export-format detection and graceful unsupported states.
- Source-layout toggle can become expensive if it tries to render every original format. Start with cached local/PDF/HTML viewers and add richer viewers incrementally.
- Offline cache must avoid leaking content through logs, filenames, shared storage, or backups.

### Recommended implementation order

This plan is intentionally split into three shippable milestones. The first pass should deliver reliable Drive reading before taking on cloud sync, Slides, or full source reconstruction.

#### Milestone A: Reliable Drive reading

1. Harden auth enough for safe restore, connect, disconnect, refresh, and user-facing errors.
2. Normalize `drive://{fileId}` identity.
3. Add local Drive progress and Continue Reading support.
4. Keep online import/read support for Google Docs, PDFs, EPUBs, text, and HTML.
5. Add basic parser cleanup and representative tests.

#### Milestone B: Offline and metadata

1. Add user-controlled offline cache.
2. Add cache invalidation by Drive modified time.
3. Prefer Google Docs HTML export where it improves structure.
4. Add metadata/TOC extraction and section navigation.
5. Add source-layout toggle for PDF/HTML/text where source material is already cached or exportable.

#### Milestone C: Cross-device sync and advanced polish

1. Add opt-in Drive `appDataFolder` progress sync.
2. Add conflict resolution and offline remote-sync queueing.
3. Add Slides support where Drive export quality is good enough.
4. Add structure-aware pacing refinements.
5. Add ORP edge-case polish and optional synced WPM metadata.

### MVP cutline

The MVP acceptance line is: a user can connect Google Drive, browse supported files, open a Drive document in the reader, resume local progress using `drive://{fileId}`, and disconnect safely.

Not MVP: cross-device cloud progress sync, Slides support, full source-layout viewer, advanced TOC extraction, and structure-aware pacing.

## 2. Current-State Assessment

### What already exists

- `lib/features/content/providers/google_drive_auth_provider.dart`: checking/loading/authenticated/error states, restore on provider build, connect/disconnect, safe error messages.
- `lib/features/content/services/google_drive_auth_service.dart`: secure storage, read-only Drive scope, `google_sign_in` account restore/sign-in, and scoped Drive authorization header retrieval.
- `lib/features/content/services/google_drive_client.dart`: Drive v3 REST listing, metadata, binary download, Google Doc export, typed Drive errors.
- `lib/features/content/models/google_drive_file.dart`: supported MIME constants, `sourceId => drive://{id}`.
- `lib/features/content/providers/google_drive_files_provider.dart`: file list states and import provider for Google Docs, PDF, EPUB, text, HTML.
- `lib/features/content/widgets/google_drive_source_panel.dart` and `lib/screens/sources_screen.dart`: Drive source UI and `/read-drive` navigation.
- `lib/features/reading/providers/reading_progress_provider.dart`: cross-source local progress keyed by stable content ID.
- `lib/features/content/services/reading_progress_sync.dart`: debounced local/remote progress write helper, currently Instapaper-oriented.
- `lib/features/content/services/content_normaliser.dart`, `lib/services/pdf_extractor.dart`, `lib/services/epub_extractor.dart`: usable parsing pipeline.
- `lib/features/reading/pacing/word_duration.dart`: punctuation, abbreviation, complexity, and long-word timing already exist.
- `lib/core/orp.dart`, `lib/core/word_timer.dart`, `lib/core/wpm_dial_notifier.dart`: existing pacing, ORP, and WPM surfaces.

### What should be reused

- Reuse `drive://{fileId}` as the canonical content identity.
- Reuse `ReadingProgress` for local Drive progress.
- Generalize `ReadingProgressSync` instead of creating a second sync timer.
- Reuse `ContentNormaliser` for Docs/HTML/text cleanup.
- Reuse PDF/EPUB extraction and existing page/chapter boundaries.
- Reuse go_router `/read-drive`, then extend route extras for cached source references and metadata.

### What must not be rebuilt

- ORP engine, word timer, WPM dial, gesture system, ContextReveal, PDF/EPUB extractors, library import structure, existing auth/list/import foundation.

## 3. Architecture Proposal

### New/changed modules

- Change `lib/features/content/services/google_drive_auth_service.dart`
  - Android uses `google_sign_in` scoped authorization headers for Drive REST calls.
  - Add capability state for `drive.readonly` vs optional `drive.appdata`.
  - Ensure no token, header, or file metadata logging.
- Change `lib/features/content/providers/google_drive_auth_provider.dart`
  - Add `GoogleDriveAuthAuthenticated.capabilities`.
  - Add `reauthorizeForProgressSync()` only when the user opts into cloud progress.
- Change `lib/features/content/services/google_drive_client.dart`
  - Add resumable or streaming downloads with progress callbacks.
  - Add export format helpers: Docs HTML/text, Slides supported export probing.
  - Add `appDataFolder` JSON read/write methods behind optional scope.
  - Add response handling for 401 refresh/retry, 403 permission, 429 retry-after.
- Create `lib/features/content/models/drive_content_identity.dart`
  - Holds `sourceId`, `fileId`, revision/modified time, MIME type, and title.
- Create `lib/features/content/models/drive_progress_record.dart`
  - Remote-safe progress metadata with no document text.
- Create `lib/features/content/services/google_drive_progress_sync_service.dart`
  - Optional appDataFolder-backed progress sync.
- Create `lib/features/content/services/google_drive_offline_cache.dart`
  - App-private cache index, content files, export metadata, eviction.
- Create `lib/features/content/providers/google_drive_cache_provider.dart`
  - Cache state, download progress, offline availability, clear cache.
- Create `lib/features/content/models/document_metadata.dart`
  - Title, author, headings, page boundaries, slide boundaries, TOC, confidence.
- Create `lib/features/content/services/document_metadata_extractor.dart`
  - Heuristics for text, HTML, PDF, EPUB, and Slides.
- Create `lib/features/content/services/drive_document_parser.dart`
  - Dispatches MIME-specific extraction and returns document, metadata, and source reference.
- Create source-layout viewer files under `lib/features/content/widgets/` or `lib/features/reading/source_viewer/`.

### Data models

#### `DriveContentIdentity`

- `sourceId: drive://{fileId}`
- `fileId`
- `name`
- `mimeType`
- `modifiedTime`
- `sizeBytes`
- `exportMimeType`
- `sourceRevisionKey`, initially derived from modified time unless a stronger Drive revision signal is added.

#### `DriveProgressRecord`

- `sourceId`
- `fileId`
- `wordIndex`
- `totalWords`
- `progress`
- `updatedAt`
- `deviceId`
- `sourceModifiedTime`
- `wpm`
- Optional `sectionId` or `pageNumber`
- Must not include text, excerpts, headings, file contents, auth data, or raw headers.

#### `DriveOfflineCacheEntry`

- `sourceId`
- `fileId`
- `name`
- `mimeType`
- `exportMimeType`
- `modifiedTime`
- `localPath`
- `bytes`
- `cachedAt`
- `lastAccessedAt`
- `pinnedOffline`
- `parseStatus`

#### `DocumentMetadata`

- `title`
- `author`
- `sections`
- `toc`
- `pageBoundaries`
- `slideBoundaries`
- `confidence`

#### `DocumentSection`

- `id`
- `title`
- `level`
- `startWordIndex`
- `startSentenceIndex`
- `pageNumber`
- `confidence`

### Providers/services

- Keep `googleDriveAuthProvider` and `googleDriveFilesProvider`.
- Split import into parser/cache/progress services so `GoogleDriveImport` orchestrates instead of doing MIME work inline.
- Add `googleDriveOfflineCacheProvider`.
- Add `googleDriveProgressSyncProvider`.
- Add `driveDocumentMetadataProvider(sourceId)`.
- Add `sourceLayoutControllerProvider(sourceId)` for toggle state and return position.

### Routing/UI changes

- Extend `/read-drive` extras with:
  - `identity`
  - `metadata`
  - `cachedSourcePath`
  - `originalViewKind`
- Add route `/read-drive/source-layout`.
- Pass `sourceId`, current `wordIndex`, and source-view descriptor via `extra`.
- Use go_router only for route transitions.
- Add UI states:
  - disconnected
  - restoring session
  - connected
  - permission needed
  - refreshing
  - downloading
  - cached offline
  - cache stale
  - offline unavailable
  - sync disabled
  - sync pending
  - sync conflict
  - unsupported export/type

### Privacy/security constraints

- Default scope remains `drive.readonly`.
- Optional cloud progress sync must require explicit user opt-in and additional scope.
- Do not modify original Drive documents.
- Do not store text content remotely.
- Do not log tokens, auth headers, file contents, raw filenames in diagnostic logs unless already user-visible UI context requires it.
- Prefer app-private directories. Consider platform encrypted storage for small metadata; large cached documents should be app-private and clearable.

### Performance budgets

- Auth restore must not block app launch UI. The Drive panel can show a checking/restoring state while the rest of the app remains interactive.
- File listing must paginate and request only required metadata fields. Do not fetch file contents or broad metadata during browse/search.
- Online import must show a loading/progress state for large downloads and long parsing jobs.
- Reader startup must never wait on cloud progress sync. Use the best local position immediately, then reconcile remote progress later if sync is enabled.
- PDF extraction must continue to respect the pdfrx main-isolate constraint; expensive classification/normalization work should stay off the main event loop where allowed.
- Cache eviction and stale checks should run incrementally, not as a blocking app-start sweep.

### Lifecycle behavior

- Flush local progress on pause, background, and reader dispose.
- Queue remote sync when offline or when Drive auth is unavailable; retry only after connectivity/auth restore.
- Cancel downloads safely if the app exits or the user cancels; remove partial files unless they can be resumed safely.
- Mark cache entries as pending/failed atomically so stale partial files do not appear available offline.
- Exclude cached documents from cloud backups where platform-appropriate.
- On disconnect, clear auth data and disable remote sync. Local progress and user-controlled offline cache should remain unless the user chooses to clear them.

### Product defaults

- Default behavior: local-only progress using `drive://{fileId}`.
- Optional behavior: cross-device progress sync through Drive `appDataFolder`.
- Never modify original Drive files.
- Never silently expand Drive permissions. Additional scopes require an explicit, contextual opt-in.

## 4. Dependency-Ordered Backlog

Backlog tasks are grouped by milestone. Dependencies should be interpreted within and across these groups, but Milestone A is the first implementation target.

### Milestone A: Reliable Drive reading

### GDI-M2-01: Harden Drive auth lifecycle

<!-- GDI-M2-01 completed up to this point -->

- Goal: Make auth restore, refresh, disconnect, and platform errors reliable.
- Files likely touched: `google_drive_auth_service.dart`, `google_drive_auth_provider.dart`, auth tests.
- Implementation notes: Add Android refresh-token exchange, one-shot 401 retry, capability flags, better cancellation/permission/rate-limit states, no sensitive logs.
- Dependencies: none.
- Tests: auth restore, expired token refresh, revoked token, user cancellation, missing client ID, disconnect clears secure storage.
- Acceptance criteria: Drive restores on app start, refreshes without user prompt when possible, prompts only when needed, never logs secrets.
- Estimated size: M

### GDI-M2-02: Normalize Drive identity model
<!-- GDI-M2-02 completed up to this point -->

- Goal: Centralize `drive://{fileId}` identity and file revision metadata.
- Files likely touched: `google_drive_file.dart`, new `drive_content_identity.dart`, router/import tests.
- Implementation notes: Include modified time, MIME, export MIME, and source revision key.
- Dependencies: none. This can start before full auth hardening because it is a local model cleanup.
- Tests: identity serialization, stable source ID, modified-time changes.
- Acceptance criteria: All Drive progress/cache/import paths use one identity model.
- Estimated size: S

### GDI-M2-03: Local Drive progress persistence
<!-- first unit of work completed up to this point -->

- Goal: Store Drive reading progress locally through existing shelf/bookmark systems.
- Files likely touched: `parallax_reading_screen.dart`, `reading_progress_provider.dart`, `app_router.dart`.
- Implementation notes: Treat `drive://` as source `drive`, not clipboard/local. Resume Drive docs from local progress.
- Dependencies: GDI-M2-02.
- Tests: Drive shelf record, resume index, mark finished, duplicate prevention.
- Acceptance criteria: Drive imports appear in Continue Reading and resume correctly.
- Estimated size: M

### GDI-M2-04: Generalize debounced progress sync
<!-- first unit of work completed up to this point -->

- Goal: Make `ReadingProgressSync` source-agnostic.
- Files likely touched: `reading_progress_sync.dart`, tests.
- Implementation notes: Replace Instapaper-only fields with optional remote writer strategy. Keep existing Instapaper behavior.
- Dependencies: GDI-M2-03.
- Tests: local-only, Instapaper remote, Drive remote, debounce, flush-on-pause.
- Acceptance criteria: No regressions for Instapaper; Drive can plug in remote writer.
- Estimated size: M

### GDI-M2-04A: Reliable online Drive parsing cleanup

- Goal: Keep current online import/read flows reliable before adding offline cache or advanced exports.
- Files likely touched: `google_drive_files_provider.dart`, `content_normaliser.dart`, `google_drive_client.dart`, import tests.
- Implementation notes: Preserve existing Docs/plain text/PDF/EPUB/HTML imports; improve safe errors, parser loading states, unsupported-file handling, and large-file progress messaging.
- Dependencies: GDI-M2-01, GDI-M2-02.
- Tests: Docs text import, PDF/EPUB delegation, HTML/text import, unsupported MIME, network/rate-limit/import error states.
- Acceptance criteria: Milestone A MVP works online with local progress and no sensitive logs.
- Estimated size: M

### Milestone B: Offline and metadata

### GDI-M2-07: Offline cache foundation

- Goal: Add app-private cache index and storage service.
- Files likely touched: new `google_drive_offline_cache.dart`, `google_drive_cache_provider.dart`, model tests.
- Implementation notes: Store cache entries by source ID, validate modified time, set size cap, LRU eviction excluding pinned offline files.
- Dependencies: GDI-M2-02.
- Tests: add/read/invalidate/evict/clear cache.
- Acceptance criteria: Cache metadata is deterministic and clearable.
- Estimated size: L

### GDI-M2-08: Download progress and retry behavior

- Goal: Support controlled offline downloads.
- Files likely touched: `google_drive_client.dart`, cache provider, source panel.
- Implementation notes: Stream bytes, expose progress, retry transient network/rate-limit with backoff, support cancel.
- Dependencies: GDI-M2-07.
- Tests: progress stream, retry, cancellation, partial download cleanup.
- Acceptance criteria: User can make supported files available offline and see status.
- Estimated size: M

### GDI-M2-09: MIME/export expansion

- Goal: Add Docs HTML export and Slides parsing strategy.
- Files likely touched: `google_drive_file.dart`, `google_drive_client.dart`, `drive_document_parser.dart`.
- Implementation notes: Prefer Docs HTML for structure; fallback to text. For Slides, probe supported export formats and start with plain text/HTML/PDF extraction if supported. Docs HTML export can ship before offline caching; Slides should stay Milestone C unless it proves low risk.
- Dependencies: GDI-M2-02 for Docs HTML. Offline cache is optional, not required. Slides depends on explicit export feasibility work.
- Tests: Docs HTML, Docs text fallback, Slides supported/unsupported, unsupported file messaging.
- Acceptance criteria: Supported export paths produce readable text; unsupported exports never crash.
- Estimated size: M

### GDI-M2-10: Metadata extraction schema

- Goal: Add title/author/headings/page/slide/TOC metadata.
- Files likely touched: new `document_metadata.dart`, `document_metadata_extractor.dart`, `models.dart`.
- Implementation notes: Add confidence levels and fallback metadata when weak.
- Dependencies: GDI-M2-09.
- Tests: plain text, Docs HTML, PDF boundaries, EPUB chapters, Slides boundaries.
- Acceptance criteria: Parser returns metadata with confidence and never blocks reading.
- Estimated size: L

### GDI-M2-11: Source-layout toggle route

- Goal: Let users jump from paced reading to original context and back.
- Files likely touched: `app_router.dart`, `parallax_reading_screen.dart`, new source viewer widgets.
- Implementation notes: Preserve current word index; PDF viewer first, HTML/text viewer second, Slides fallback if cached/exported.
- Dependencies: GDI-M2-07, GDI-M2-10.
- Tests: route push/pop, exact word restore, offline cached layout, unsupported layout state.
- Acceptance criteria: Toggle does not reset timer/ORP/progress.
- Estimated size: L

### GDI-M2-12: Section navigation and TOC UI

- Goal: Use metadata for reader navigation.
- Files likely touched: reader widgets, metadata provider, tests.
- Implementation notes: Add section drawer/sheet using design tokens, no color-only signals.
- Dependencies: GDI-M2-10.
- Tests: section tap seeks correct word, weak metadata fallback, accessibility labels.
- Acceptance criteria: Users can jump to headings/pages/slides without losing reading state.
- Estimated size: M

### Milestone C: Cross-device sync and advanced polish

### GDI-M2-05: Cloud progress architecture decision and opt-in UI

- Goal: Add explicit privacy-preserving progress sync choice.
- Files likely touched: settings/source UI, auth provider, new progress settings model.
- Implementation notes: Default off. Explain that content is not uploaded. Request extra scope only after opt-in.
- Dependencies: GDI-M2-04.
- Tests: opt-in state, declined scope, disconnect disables sync.
- Acceptance criteria: Reviewer can verify no remote writes happen unless user opts in.
- Estimated size: M

### GDI-M2-06: appDataFolder progress sync service

- Goal: Sync Drive progress without modifying original documents.
- Files likely touched: `google_drive_client.dart`, new `google_drive_progress_sync_service.dart`, provider/tests.
- Implementation notes: Store one JSON manifest in `appDataFolder`; merge by `updatedAt`, `sourceModifiedTime`, `deviceId`. Treat this as a later epic, not part of the first Drive milestone.
- Dependencies: GDI-M2-05.
- Tests: upload/download manifest, conflict resolution, offline queue, corrupted remote JSON.
- Acceptance criteria: Multiple devices converge without content upload or document mutation.
- Estimated size: L

### GDI-M2-13: Punctuation pacing refinement

- Goal: Extend existing punctuation pacing with paragraphs/headings/lists.
- Files likely touched: `word_duration.dart`, `pacing_config.dart`, metadata/token models.
- Implementation notes: Do not create a second timer. Add boundary-aware timing input to `durationForWord` or word-source metadata.
- Dependencies: GDI-M2-10.
- Tests: commas, colons, semicolons, periods, abbreviations, decimals, paragraphs, headings, list boundaries.
- Acceptance criteria: Timing changes are deterministic and configurable.
- Estimated size: M

### GDI-M2-14: Drive tokenization and ORP edge cases

- Goal: Keep Drive-imported text clean for ORP.
- Files likely touched: `ContentNormaliser`, ORP tests, parser tests.
- Implementation notes: Normalize quotes, hyphenation, soft line breaks, non-breaking spaces, slide bullets.
- Dependencies: GDI-M2-09.
- Tests: quotes, punctuation, hyphenation, long words, HTML entities, Docs exports.
- Acceptance criteria: ORP anchor remains stable across Drive-imported content.
- Estimated size: M

### GDI-M2-15: Dynamic speed continuity

- Goal: Adjust WPM mid-session without losing Drive progress.
- Files likely touched: `word_timer.dart`, `wpm_dial_notifier.dart`, config/progress models.
- Implementation notes: Existing `setWpm` restarts timer; add tests for no index reset and persistence into Drive progress metadata.
- Dependencies: GDI-M2-03 for local continuity. Synced WPM metadata depends on GDI-M2-06 and is not required for Milestone A.
- Tests: gesture, keyboard shortcut, reduced motion, persisted WPM, synced WPM.
- Acceptance criteria: WPM updates immediately and current word position is preserved.
- Estimated size: S/M

## 5. Feature-by-Feature Plan

### Seamless Authentication

- Use existing auth service/provider as the base.
- Keep `drive.readonly` for browsing/import.
- Add Android token refresh using stored refresh token.
- On 401, refresh once and retry the Drive request; if refresh fails, transition to reconnect-needed.
- Separate user cancellation from auth failure.
- Add account label, connected status, disconnect confirmation, reconnect-needed state.
- Platform concerns:
  - iOS: require iOS OAuth client ID, URL schemes, `GoogleSignIn.initialize`.
  - Android: require Google Sign-In configuration with `GOOGLE_WEB_CLIENT_ID` as `serverClientId` or a selected `google-services.json`; keep Android package/SHA configured for `com.runthru.app`.
- Tests: restore, connect, disconnect, expired token, cancellation, rate limit, network, missing config, no sensitive logs.
- Acceptance criteria: app start restores Drive safely; connect/disconnect are explicit; only read-only file access is requested by default.

### Cloud Bookmarks & Sync

- Local source ID: `drive://{fileId}`.
- Local progress store: `ReadingProgress` plus existing bookmark/config path until a unified repository is created.
- Remote options:
  - Recommended: Drive `appDataFolder` JSON manifest, opt-in, additional app-data scope. Does not modify original files and is hidden from normal Drive UI.
  - Sidecar file in user Drive: user-visible and more privacy risk; avoid unless user explicitly chooses.
  - File `appProperties`: modifies original Drive file metadata and needs write permission; reject for this milestone.
  - RunThru backend: broader privacy/compliance surface; reject for now.
- Conflict policy:
  - If same source modified time, newest `updatedAt` wins.
  - If remote source modified time differs, preserve both local and remote records and ask user to resume latest compatible position.
  - Tie-break by device ID only for deterministic merges.
- Offline: queue latest pending progress locally; sync on reconnect/auth restore.
- Debounce: write local every meaningful interval; remote no more than every 30-60 seconds and always flush on pause/background.
- Acceptance criteria: no content text synced; original Drive documents untouched; sync is off until opt-in.

### Offline Caching

- Add "Make available offline" action per file.
- Cache exported Docs/Slides output, PDFs, EPUBs, text, HTML.
- Invalidate when Drive `modifiedTime` changes.
- Keep pinned offline files until user clears/removes them.
- Evict unpinned cache by LRU under size cap.
- Store under app-private documents/cache directory.
- UI states: downloading, available offline, stale, failed, retry, clear cache.
- Acceptance criteria: offline cached file opens without network; stale files refresh when online.

### Text Extraction

- Docs: export HTML first for structure, fallback to plain text.
- PDFs: use existing `pdfExtract`; scanned/image-only returns clear unsupported OCR-needed message.
- EPUBs: existing extractor.
- Slides: probe Drive export support; prefer text/HTML if available, otherwise PDF export and PDF extraction; unsupported if no readable export.
- HTML/Markdown cleanup: route through `ContentNormaliser`, then metadata extractor.
- Heavy work: `ContentNormaliser`/EPUB in isolates; pdfrx remains main isolate.
- Acceptance criteria: readable text extraction is preferred over page rendering.

### Toggle Layout

- Add source-layout route from reader toolbar/control.
- Preserve `sourceId`, cached path/export, current word index.
- PDF: render cached PDF/source PDF using existing PDF viewer capabilities.
- Docs: show cached HTML/text export with section anchors.
- Slides: show cached exported PDF/HTML/text when available.
- Return to exact word with `resumeFromContextReveal` or direct timer seek depending play state.
- Acceptance criteria: toggle works offline for cached files and never loses reading position.

### Metadata Recognition

- Plain text: infer title from filename/first non-empty line; headings from short standalone title-case lines.
- Google Docs HTML: parse headings `h1-h6`, title, lists, tables, footnotes where export exposes them.
- PDF: use file name/title metadata if available; page boundaries from existing extractor; headings by font unavailable, so use text heuristics conservatively.
- EPUB: use OPF metadata and spine/chapter boundaries.
- Slides: each slide boundary is a section; title from first prominent text line if available.
- Confidence: high for EPUB/Docs semantic tags, medium for page/slide boundaries, low for plain-text/PDF heading heuristics.
- Acceptance criteria: weak metadata falls back gracefully to pages/sections.

### Punctuation Pausing

- Existing `durationForWord` already handles comma, dash, semicolon, colon, ellipsis, sentence punctuation, abbreviations, and initialisms.
- Add boundary-aware pauses for paragraph, heading, and list boundaries from metadata/token annotations.
- Add decimal guard tests for `3.14`, currencies, versions, numbered lists.
- Settings: keep current pacing config; optionally expose "structure pauses" under existing pacing panel.
- Acceptance criteria: one timer, deterministic timing, no over-pausing abbreviations/decimals.

### ORP Highlighting

- Normalize Drive tokens before ORP: strip leading/trailing punctuation for anchor, preserve display punctuation.
- Handle quotes, smart quotes, hyphenated words, soft hyphen, long URLs, bullets.
- Ensure source-layout toggle preserves `currentIndex` and word source.
- Test with Drive Docs HTML, Slides bullets, PDF line-break hyphenation.
- Acceptance criteria: ORP anchor is stable and accessible settings still apply.

### Dynamic Speed Control

- Reuse WPM dial and `WordTimerNotifier.setWpm`.
- Add keyboard shortcuts for desktop/tablet where supported.
- Respect reduced motion for dial/feedback.
- Optional haptic/non-color feedback on mobile.
- Persist WPM in config and include last WPM in optional Drive progress metadata.
- Acceptance criteria: WPM changes immediately without resetting current word.

## 6. Test Strategy

### Unit tests

- Drive identity.
- Cache index.
- Progress conflict resolution.
- Metadata extraction.
- MIME support.
- Export decisions.
- Punctuation timing.
- ORP tokenization.

### Provider tests

- Auth states.
- File list states.
- Cache provider states.
- Import states.
- Sync queued/synced/conflict states.

### Widget tests

- Drive source panel connected/disconnected/error/offline states.
- Offline action.
- Clear cache UI.
- Sync opt-in UI.
- Source-layout button.
- TOC navigation.

### Integration tests

- Import Drive file to reader.
- Resume Drive progress.
- Toggle source layout and return.
- WPM adjust mid-read.
- Offline cached open.

### Offline/sync tests

- Offline progress queued.
- App restart retains queue.
- Reconnect reconciles.
- Modified-time conflict.
- Stale cache invalidation.

### Privacy/logging tests

- Log capture asserts no access token, auth header, refresh token, file contents, or remote progress payload text.

## 7. Verification Commands

```sh
flutter pub get
dart run build_runner build --delete-conflicting-outputs
dart analyze --fatal-infos
flutter test
```

## 8. Risks & Open Questions

### Google Drive API limitations

- `files.list` returns partial metadata unless requested with `fields`.
- `appDataFolder` requires `spaces=appDataFolder` and an app-data scope.
- Rate limits and export limits need retry/backoff and user-safe errors.
- Mitigation: keep Milestone A read-only and local-only; isolate `appDataFolder` behind a later opt-in epic; add one-shot 401 refresh/retry and bounded exponential backoff for 429/network failures.

### Google Docs/Slides export limitations

- Docs HTML/text export may lose some layout context.
- Slides text extraction may be incomplete; runtime export-format probing is needed.
- Scanned PDFs require OCR, which should remain out of scope unless explicitly planned.
- Mitigation: ship Docs/PDF/EPUB/text/HTML first; keep Slides behind a feasibility task; show clear unsupported messaging for scanned PDFs and poor export results.

### Cloud progress storage decision

- Strict read-only Drive access means no Drive-backed cross-device progress writes.
- Recommended path is opt-in `appDataFolder`; otherwise keep local-only progress.
- Mitigation: make local-only progress the default and first shipped behavior. Treat appDataFolder sync as Milestone C with a separate permission-review checklist.

### Offline cache storage limits

- Need a default cap, user-facing clear cache, LRU eviction, and pinned offline protection.
- Mitigation: start with an explicit user action for offline availability, app-private storage, modified-time invalidation, partial-download cleanup, and a visible clear-cache control.

### Privacy implications

- Cached documents are local copies of user content.
- Remote progress metadata can reveal reading behavior and document IDs, even without text.
- Sync must be opt-in and clearly scoped.
- Mitigation: do not upload text, excerpts, headings, titles beyond what is required for identity if avoidable; document remote metadata fields; exclude cache from backups where supported; add privacy/logging tests.

### Source-layout scope creep

- "Show original document" can grow into a full document viewer project.
- Mitigation: Milestone B supports only source views that are already cached/exported and technically straightforward: PDF, HTML, and plain text. Full-fidelity Docs/Slides rendering is explicitly out of scope unless added as a separate viewer milestone.

## 9. Final Acceptance Criteria

### Milestone A merge checklist

- [ ] Google Drive appears as a reliable source entry.
- [ ] User can connect, restore, and disconnect Google Drive safely.
- [ ] User can browse supported Drive files without fetching file contents during listing.
- [ ] User can open Google Docs, PDFs, EPUBs, text, and HTML in the reader through the existing Drive import flow.
- [ ] Drive reader sessions use `drive://{fileId}` as the stable local content ID.
- [ ] Drive reading progress resumes locally and appears in Continue Reading.
- [ ] Reader startup does not wait on cloud progress sync.
- [ ] Unsupported files, network failures, auth failures, cancellation, permission errors, rate limits, and scanned PDFs show safe user-facing messages.
- [ ] No tokens, auth headers, file contents, or sensitive Drive metadata are logged.
- [ ] Verification commands pass.

### Full plan checklist

- [ ] Google Drive auth restores on app start and handles expiry/revocation safely.
- [ ] Default Drive file access uses read-only scopes only.
- [ ] Optional cloud progress sync is off by default and uses explicit opt-in.
- [ ] Drive progress is keyed by `drive://{fileId}` locally.
- [ ] Original Drive documents are never modified for progress sync.
- [ ] No document text is uploaded for progress sync.
- [ ] Offline files can be pinned, opened offline, invalidated when stale, and cleared.
- [ ] Docs, PDFs, EPUBs, text, HTML, and feasible Slides exports parse into readable text.
- [ ] Scanned/image-only PDFs show a clear unsupported/OCR-needed state.
- [ ] Source-layout toggle preserves exact reading position.
- [ ] Metadata extraction provides title, headings/sections, page or slide boundaries, TOC, and confidence.
- [ ] Punctuation/structure pauses use the existing word timer.
- [ ] ORP remains correct for Drive-imported punctuation, quotes, hyphenation, and long words.
- [ ] WPM can change mid-session without resetting word position.
- [ ] UI uses design tokens, typography tokens, accessible labels, and no raw progress indicators.
- [ ] Navigation uses go_router.
- [ ] Public symbols have Dartdoc comments.
- [ ] Riverpod generated files are updated.
- [ ] Analyzer and tests pass with the required verification commands.
