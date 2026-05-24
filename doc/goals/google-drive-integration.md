# Goal: Complete Google Drive Integration

You are Codex 5.5 working in the RunThru Flutter/Dart repo.

## Objective

Implement Google Drive as a first-class content source so users can:

1. Connect their Google Drive account.
2. Browse or search supported Drive files.
3. Import readable files.
4. Convert imported content into the app’s existing document model.
5. Open the imported document in the existing paced reading flow.

Mirror the existing Instapaper integration patterns where useful, but keep all Google Drive code clearly named and separate.

## Inspect First

Read these before coding:

- `AGENTS.md`
- `.github/copilot-instructions.md`
- `lib/screens/sources_screen.dart`
- `lib/navigation/app_router.dart`
- `lib/features/content/providers/instapaper_auth_provider.dart`
- `lib/features/content/providers/instapaper_bookmarks_provider.dart`
- `lib/features/content/widgets/instapaper_auth_tile.dart`
- `lib/features/content/widgets/instapaper_bookmark_list.dart`
- `lib/features/content/services/content_normaliser.dart`
- `lib/features/content/services/library_import.dart`
- `lib/services/models.dart`
- `lib/services/pdf_extractor.dart`
- `lib/services/epub_extractor.dart`
- `pubspec.yaml`

## Scope

Support these Drive file types:

- Google Docs: export as plain text or HTML, then normalize.
- PDF: download and use the existing PDF extraction pipeline.
- EPUB: download and use the existing EPUB extraction pipeline if already supported.
- Plain text / HTML: normalize through the existing content normalizer.

Unsupported file types must not crash the app. Either filter them out or clearly mark them unsupported.

## Architecture Requirements

Follow existing repo rules:

- Put new feature code under `lib/features/content/`.
- Use Riverpod for auth, file list, import, and refresh state.
- Use `go_router`; do not use `Navigator.push`.
- Store OAuth tokens only in secure storage.
- Never log tokens, auth headers, file contents, or sensitive Drive metadata.
- Keep imported reading content on-device.
- Use existing design tokens, typography tokens, and decoration factories.
- Do not use raw progress indicators.
- Add Dartdoc comments to public symbols.
- Regenerate Riverpod `.g.dart` files after provider changes.

## Implementation Tasks

### 1. Auth

Create:

- `google_drive_auth_service.dart`
- `google_drive_auth_provider.dart`

Implement:

- sign in
- restore session
- sign out
- authenticated / unauthenticated / loading / error states
- minimal read-only Drive scopes
- secure token storage
- safe user-facing error messages

### 2. Drive Client

Create:

- `google_drive_client.dart`
- `google_drive_file.dart`

Implement:

- list supported files
- search files by name
- fetch file metadata
- download binary files
- export Google Docs
- typed errors for auth, permission, rate limit, network, unsupported MIME type, and unexpected response

### 3. File List Provider

Create a Riverpod provider that supports:

- not connected
- loading
- loaded
- empty
- refreshing
- error

It should auto-refresh after sign-in and work independently from other sources.

### 4. Import Flow

Create a Google Drive import provider with states for:

- idle
- loading
- done
- error

Import behavior:

- Google Docs → export → normalize → document
- PDF → download temp/cache file → existing PDF extractor
- EPUB → download temp/cache file → existing EPUB extractor
- text/HTML → normalize

On success, open the existing reader with the imported document.

Use stable source IDs:

```txt
drive://{fileId}

Do not sync reading progress back to Google Drive.

5. UI

Update the Sources screen to include Google Drive.

Add:

connect tile
connected account state if available
disconnect action
file list or Drive entry point
refresh
loading / empty / error states
accessible semantics labels

Keep UI consistent with existing RunThru components and design rules.

6. Tests

Add tests for:

auth state transitions
file list parsing
unsupported MIME filtering
Google Doc export normalization
PDF/EPUB import delegation
import loading → done
import loading → error
Sources screen disconnected state
Sources screen connected state
tapping a supported Drive file starts import
reading navigation uses go_router

Use existing test patterns with Riverpod and mocktail.

Verification

Run:

flutter pub get
dart run build_runner build --delete-conflicting-outputs
dart analyze --fatal-infos
flutter test
Acceptance Criteria
Google Drive appears as a source.
User can connect and disconnect Google Drive.
User can list supported Drive files.
User can import a Google Doc and read it.
User can import a Drive PDF and read it.
Unsupported files do not crash the app.
Tokens are stored securely.
No tokens or document contents are logged.
UI follows RunThru design and accessibility rules.
Navigation uses go_router only.
Public symbols have Dartdoc comments.
Generated files are updated.
Analyzer and relevant tests pass.
Final Response Required

When finished, report:

Summary of changes.
Files created.
Files modified.
Dependencies added and why.
Google Cloud Console setup still required.
Test results.
Known limitations or follow-up tasks.
