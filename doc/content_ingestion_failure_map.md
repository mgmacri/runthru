# Content Ingestion Failure Map

## File Picker / Local Files

| Path | Success | Cancel | Empty/unsupported | Duplicate | Bad document | Renderer risk | Recovery |
|---|---|---|---|---|---|---|---|
| Desktop file picker | Referenced `LibrarySource.file`; scanned as PDF/EPUB | No-op | Picker filters PDF/EPUB; classifier rejects unsupported | Deduped by canonical locator/source key | Extractor marks unsupported/error/permanent failure | Reader uses extraction pipeline | Retry preprocessing or remove source |
| Mobile file picker | Copies selected books into owned source | No-op | Snack if no files | Collision-safe filenames; source dedupe | Extractor marks typed failure | Reader uses extraction pipeline | Retry/remove |

## Folder Import

| Path | Success | Cancel | Empty/unsupported | Duplicate | Title | Recovery |
|---|---|---|---|---|---|---|
| Android SAF folder | Native copy to owned app directory; stable `android-tree:<treeUri>` key | Deletes temp dir | Snack: no supported books | Source key canonicalizes trailing slash | Uses native `displayName`; derives from tree URI before `Imported folder` | Retry picker |
| iOS folder | Security-scoped copy to owned app directory | No-op | Snack: no supported books | `ios-folder:<path>` source key | Basename of picked path | Retry picker |
| Desktop folder | References folder in place | No-op | Empty library state | Canonical path | Basename | Remove/re-add |

## Scan / Dedupe / Preprocessing

| Failure | Typed State | Logging | Test |
|---|---|---|---|
| Same folder added twice | `addFolder` returns `false` | `library_sources` duplicate | `library_sources_test.dart` |
| Same SAF tree with trailing slash | `addFolder` returns `false` | `library_sources` duplicate | `library_sources_test.dart` |
| Same book in default and imported folders | Single `PdfEntry`, referenced copy wins | `folder_scanner` | `folder_scanner_test.dart` |
| Repeated scan refresh | Queue dedupes by logical book key | `preprocessing` dedupe | targeted queue/model tests |
| Unsupported extension/signature | `PdfStatus.unsupported` | `preprocessing` unsupported | `document_classifier_test.dart` |
| Timeout | `PdfStatus.error`, then retry/permanent failure | `preprocessing` timeout | extractor timeout model tests |

## Extraction / Routing

| Document | Route | Bad Path Handling |
|---|---|---|
| PDF | `pdf_extractor` and PDF-only range picker | pdfrx errors replaced with app-level range error UI |
| EPUB | `epub_extractor`; no range picker | Library long-press range action disabled; direct range route shows PDF-only message |
| Text/HTML/Google Doc | Content normaliser into clipboard-style reader | No pdfrx routing |
| Missing/corrupt/unsupported | Extraction error states | User sees non-crashing failed/unsupported library state |

## Connected Services

| Service | Auth Missing | Cancel | Expired/Revoked | Network | Permission | Retry |
|---|---|---|---|---|---|---|
| Google Drive | `GoogleDriveAuthUnauthenticated` / `authRequired` messages | `userCancelled` error | `expiredToken`, reconnect copy | `network` | `permission` | Explicit Connect/Refresh |
| Instapaper | Restore returns unauthenticated | `userCancelled` reserved typed kind | `unauthorized`, clears invalid tokens | `network` | `permissionDenied` reserved typed kind | Official connect first, legacy fallback explicit |

## Provider Lifecycle

`PreprocessingQueue` no longer enqueues from synchronous construction. It
subscribes/enqueues after provider creation, avoiding provider state writes
while Flutter/Riverpod is building widgets.
