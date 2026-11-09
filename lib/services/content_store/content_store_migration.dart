/// Incremental migration from the legacy flat `pdf_cache` into the Ring 2
/// content store.
///
/// Strategy: **migrate on touch.** Whenever a legacy cache entry is read
/// (queue rehydration, cache hit at scan), the document is ingested into the
/// store under its content hash — one book per pass, idempotent (manifest +
/// schema version checked), with the legacy file left in place until the
/// shared LRU budget reclaims it. A crash mid-ingest leaves no manifest, so
/// the book is simply re-ingested on the next touch; nothing is deleted.
///
/// This file provides the dry-run report: what *would* be migrated, without
/// doing it.
library;

import 'package:runthru/core/logger.dart';
import 'package:runthru/services/content_identity.dart';
import 'package:runthru/services/content_store/content_store.dart';

/// Dry-run inspection of pending legacy-cache migrations.
class ContentStoreMigration {
  ContentStoreMigration._();

  /// Returns the file paths whose content is not yet in the store (they
  /// will be ingested on next touch). Logs a bounded summary — never the
  /// full list.
  static Future<List<String>> dryRunReport({
    required List<String> filePaths,
    required ContentStore store,
    required ContentIdentityService identity,
  }) async {
    final pending = <String>[];
    for (final path in filePaths) {
      final hash = await identity.knownHashFor(path);
      if (hash == null || !await store.hasBook(hash)) {
        pending.add(path);
      }
    }
    appLog(
      'content_store_migration',
      'dry run: ${pending.length} of ${filePaths.length} book(s) pending '
          'migration on touch',
    );
    return pending;
  }
}
