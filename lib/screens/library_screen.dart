import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:runthru/core/document_title.dart';
import 'package:runthru/core/time_left.dart';
import 'package:runthru/features/content/providers/document_title_provider.dart';
import 'package:runthru/design/design.dart';
import 'package:runthru/features/content/providers/google_drive_auth_provider.dart';
import 'package:runthru/features/content/providers/google_drive_files_provider.dart';
import 'package:runthru/features/content/providers/instapaper_auth_provider.dart';
import 'package:runthru/features/content/models/instapaper_bookmark.dart';
import 'package:runthru/features/content/providers/instapaper_bookmarks_provider.dart';
import 'package:runthru/features/content/services/instapaper_client.dart';
import 'package:runthru/features/content/widgets/instapaper_auth_tile.dart';
import 'package:runthru/features/content/services/google_drive_client.dart';
import 'package:runthru/features/reading/providers/reading_progress_provider.dart';
import 'package:runthru/core/sample_document.dart';
import 'package:runthru/services/folder_scanner.dart';
import 'package:runthru/services/models.dart';
import 'package:runthru/services/preprocessing_queue.dart';
import 'package:runthru/store/bookmark_store.dart';
import 'package:runthru/store/config.dart';
import 'package:runthru/store/models.dart';
import 'package:runthru/widgets/neumorphic_card.dart';
import 'package:runthru/widgets/paged_tile_well.dart';
import 'package:runthru/widgets/reading_goal_onboarding_gate.dart';
import 'package:runthru/widgets/runthru_shell_widgets.dart';

/// Content-type filter for the unified library.
enum _LibraryFilter { all, books, articles }

const int _kTilesPerPage = 4;

/// Unified library screen: Continue Reading → Books → Articles.
///
/// Organised by reading intent and content type. Source is metadata, not
/// the primary navigation structure.
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen>
    with WidgetsBindingObserver {
  _LibraryFilter _filter = _LibraryFilter.all;
  bool _isSearchOpen = false;
  String _searchQuery = '';
  bool _sampleSeeded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _seedSampleIfNeeded();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from the browser, where an article may just have been saved to
    // Instapaper: fetch the list again unless it is fresh.
    if (state != AppLifecycleState.resumed) return;
    if (!ref.read(instapaperAvailableProvider)) return;
    if (ref.read(instapaperAuthProvider) is! InstapaperAuthAuthenticated) {
      return;
    }
    unawaited(ref.read(instapaperBookmarksProvider.notifier).refreshIfStale());
  }

  void _seedSampleIfNeeded() {
    if (_sampleSeeded || !mounted) return;
    final config = ref.read(configProvider).valueOrNull;
    if (config == null) return;
    if (config.hasSeenReadingGoalOnboarding) {
      _sampleSeeded = true;
      return;
    }
    final progress = ref.read(readingProgressProvider.notifier);
    final existing = progress.getRecord(sampleContentId);
    if (existing != null) {
      _sampleSeeded = true;
      return;
    }
    _sampleSeeded = true;
    final doc = sampleExtractedDocument;
    progress.record(
      contentId: sampleContentId,
      source: 'sample',
      title: sampleTitle,
      wordIndex: 1,
      totalWords: doc.totalWords,
    );
  }

  @override
  Widget build(BuildContext context) {
    final pdfListAsync = ref.watch(pdfListProvider);
    // Perf (BK-10): the whole-queue map is NOT watched here — one book's
    // status flip must rebuild one tile, not the entire library. Tiles watch
    // their own entry via a select; the header watches the failed count.
    final failedCount = ref.watch(pdfFailedCountProvider);
    // Watch the store so the shelf rebuilds when the async load resolves and
    // whenever reading progress is recorded; `shelf` reads the resolved value.
    ref.watch(readingProgressProvider);
    final rawShelf = ref.read(readingProgressProvider.notifier).shelf;
    // Filter local shelf items to only those whose source file is still active.
    // Non-local sources (Instapaper, Drive) are always included.
    final activePaths = pdfListAsync.valueOrNull
        ?.map((e) => e.filePath)
        .toSet();
    // R-04: a build without Drive OAuth config cannot resume Drive items.
    final driveAvailable = ref.watch(googleDriveAvailableProvider);
    final shelf = rawShelf
        .where(
          (r) =>
              (activePaths == null ||
                  r.source != 'local' ||
                  activePaths.contains(r.contentId)) &&
              (driveAvailable || !r.contentId.startsWith('drive://')),
        )
        .toList();
    // Header counts what is actually here. (It used to claim "Synced just
    // now · N sources" with a count that disagreed with the Sources tab.)
    final titleCount = pdfListAsync.valueOrNull?.length ?? 0;
    // Times are given at the reader's own speed, as in the reader.
    final readerWpm =
        ref.watch(configProvider.select((c) => c.valueOrNull?.defaultWpm)) ??
        const AppConfig().defaultWpm;
    final normalizedSearchQuery = _searchQuery.trim().toLowerCase();
    final searching = normalizedSearchQuery.isNotEmpty;
    // A search narrows the whole screen, the shelf included.
    final visibleShelf = searching
        ? shelf
              .where(
                (r) => r.title.toLowerCase().contains(normalizedSearchQuery),
              )
              .toList()
        : shelf;

    // Open the reader when an Instapaper article has loaded. This is the
    // only listener: articles are opened from this screen alone.
    ref.listen<ArticleImportState>(instapaperArticleImportProvider, (
      previous,
      next,
    ) {
      if (next is! ArticleImportDone && next is! ArticleImportError) return;
      // The reader moved on while the article was loading (opened a book,
      // say): nothing is pushed or shown over what is on screen now.
      final stillHere = ModalRoute.of(context)?.isCurrent ?? true;
      // "Opening…" has had its say either way. (Snack bars follow the
      // reader from screen to screen.)
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      if (next is ArticleImportDone) {
        ref.read(instapaperArticleImportProvider.notifier).clear();
        if (!stillHere) return;
        context.push(
          '/read-instapaper',
          extra: {
            'document': next.document,
            'title': next.title,
            'bookmarkId': next.bookmarkId,
            'initialProgress': next.initialProgress,
            'progressTimestamp': next.progressTimestamp,
          },
        );
      } else if (next is ArticleImportError && stillHere) {
        final canConnect =
            next.kind == InstapaperFailureKind.unauthorized &&
            ref.read(instapaperAvailableProvider) &&
            ref.read(instapaperAuthProvider) is! InstapaperAuthAuthenticated;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.message),
            action: canConnect
                ? SnackBarAction(
                    label: 'Connect',
                    onPressed: () => showInstapaperSignIn(context, ref),
                  )
                : null,
          ),
        );
      }
    });

    // Navigate to reader on successful Drive import from Continue Reading.
    ref.listen<GoogleDriveImportState>(googleDriveImportProvider, (
      previous,
      next,
    ) {
      if (next is GoogleDriveImportDone &&
          next.origin == DriveImportOrigin.libraryResume) {
        ref.read(googleDriveImportProvider.notifier).clear();
        context.push(
          '/read-drive',
          extra: {
            'document': next.document,
            'identity': next.identity,
            'title': next.file.name,
            'fileId': next.file.id,
            'sourceId': next.identity.sourceId,
          },
        );
      } else if (next is GoogleDriveImportError &&
          next.origin == DriveImportOrigin.libraryResume) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.message),
            action: next.kind == GoogleDriveFailureKind.permission
                ? SnackBarAction(
                    label: 'Grant access',
                    onPressed: () {
                      ref
                          .read(googleDriveFilesProvider.notifier)
                          .grantAccessAndRefresh();
                    },
                  )
                : null,
          ),
        );
      }
    });

    return Scaffold(
      backgroundColor: RunThruTokens.shellBase,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // ── Header ──
            SliverToBoxAdapter(
              child: _LibraryHeader(
                failedCount: failedCount,
                titleCount: titleCount,
                isSearchOpen: _isSearchOpen,
                searchQuery: _searchQuery,
                onSearchChanged: (value) =>
                    setState(() => _searchQuery = value),
                onSearchToggle: () => setState(() {
                  _isSearchOpen = !_isSearchOpen;
                  if (!_isSearchOpen) {
                    _searchQuery = '';
                  }
                }),
              ),
            ),

            // ── Continue Reading shelf ──
            // While searching, only when something in progress matches.
            if (!searching || visibleShelf.isNotEmpty)
              SliverToBoxAdapter(
                child: _ContinueReadingShelf(
                  items: visibleShelf,
                  wpm: readerWpm,
                  hasTitles: titleCount > 0,
                  onItemTap: _onShelfItemTap,
                  continueTargetKey: libraryContinueTourTargetKey,
                ),
              ),

            // ── Filter chips ──
            SliverToBoxAdapter(
              child: _FilterChipRow(
                selected: _filter,
                onChanged: (f) => setState(() => _filter = f),
              ),
            ),

            // ── Books section ──
            if (_filter == _LibraryFilter.all ||
                _filter == _LibraryFilter.books) ...[
              pdfListAsync.when(
                data: (list) {
                  final filteredList = _filterBooks(
                    list,
                    normalizedSearchQuery,
                  );
                  return SliverToBoxAdapter(
                    child: _LibrarySection(
                      title: 'Books',
                      countLabel: _countLabel(filteredList.length, 'book'),
                      dotColor: RunThruTokens.shellTeal,
                      itemCount: filteredList.length,
                      empty: _EmptyBooksState(
                        message: normalizedSearchQuery.isEmpty
                            ? null
                            : 'No books match this search.',
                      ),
                      itemBuilder: (context, index) {
                        final entry = filteredList[index];
                        return _buildBookTile(entry: entry);
                      },
                    ),
                  );
                },
                loading: () => const SliverToBoxAdapter(
                  child: _LibrarySection(
                    title: 'Books',
                    countLabel: 'Loading',
                    dotColor: RunThruTokens.shellTeal,
                    itemCount: 0,
                    empty: _SectionLoading(),
                  ),
                ),
                error: (e, _) => SliverToBoxAdapter(
                  child: _LibrarySection(
                    title: 'Books',
                    countLabel: 'Issue',
                    dotColor: RunThruTokens.shellTeal,
                    itemCount: 0,
                    // A sentence and a way to try again, never the error's
                    // own text (its type is in the log).
                    empty: _ArticlesLoadError(
                      message: 'Could not load your books.',
                      onRetry: () => ref.invalidate(pdfListProvider),
                    ),
                  ),
                ),
              ),
            ],

            // ── Articles section ──
            if (_filter == _LibraryFilter.all ||
                _filter == _LibraryFilter.articles) ...[
              _ArticlesSliverList(query: normalizedSearchQuery),
            ],

            const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
          ],
        ),
      ),
    );
  }

  void _onShelfItemTap(ProgressRecord item) {
    // Navigate to the correct reader for the content type.
    if (item.contentId == sampleContentId) {
      context.push('/read-sample');
    } else if (item.contentId.startsWith('instapaper://')) {
      _resumeInstapaperItem(item);
    } else if (item.contentId.startsWith('drive://')) {
      _resumeDriveItem(item);
    } else {
      context.push(
        Uri(
          path: '/read',
          queryParameters: {'path': item.contentId},
        ).toString(),
      );
    }
  }

  /// Resume an Instapaper article from the Continue Reading shelf.
  ///
  /// Re-imports the article (its text is not cached locally) and lets the
  /// import listener navigate to the reader. The on-device bookmark restores
  /// the last word position.
  ///
  /// Fetching the text needs only the bookmark's ID, so an article that is
  /// not in the list on hand (not fetched yet, archived on another device,
  /// older than the newest 500) opens all the same.
  void _resumeInstapaperItem(ProgressRecord item) {
    final bookmarkId = int.tryParse(
      item.contentId.replaceFirst('instapaper://', ''),
    );
    final messenger = ScaffoldMessenger.of(context);
    if (bookmarkId == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('This article can no longer be opened.')),
      );
      return;
    }
    if (ref.read(instapaperArticleImportProvider) is ArticleImportLoading) {
      return;
    }
    final listed = ref
        .read(instapaperBookmarksProvider)
        .valueOrNull
        ?.where((b) => b.bookmarkId == bookmarkId)
        .firstOrNull;
    final bookmark =
        listed ??
        InstapaperBookmark(bookmarkId: bookmarkId, url: '', title: item.title);

    // The card itself does not change while the article loads; say so.
    // Replaced by the reader, or by the reason it could not be opened.
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Opening “${bookmark.displayTitle}”…'),
          duration: const Duration(seconds: 45),
        ),
      );
    ref.read(instapaperArticleImportProvider.notifier).importArticle(bookmark);
  }

  /// Resume a Google Drive document from the Continue Reading shelf.
  ///
  /// Re-fetches the document with read-only Drive access and lets the reader's
  /// local bookmark restore the last word position from `drive://{fileId}`.
  void _resumeDriveItem(ProgressRecord item) {
    final fileId = item.contentId.replaceFirst('drive://', '');
    if (fileId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Open this document from Google Drive to resume.'),
        ),
      );
      return;
    }

    ref
        .read(googleDriveImportProvider.notifier)
        .importFileById(fileId, origin: DriveImportOrigin.libraryResume);
  }

  void _onBookTap(PdfEntry entry) {
    context.push(
      Uri(path: '/read', queryParameters: {'path': entry.filePath}).toString(),
    );
  }

  void _onBookLongPress(PdfEntry entry) {
    HapticFeedback.mediumImpact();
    context.push(
      Uri(
        path: '/range-picker',
        queryParameters: {'path': entry.filePath},
      ).toString(),
    );
  }

  /// Books whose title, as the row shows it, or file name contains [query].
  ///
  /// The search used to look at the file name and folder path only: a book
  /// shown as "Alice's Adventures in Wonderland" (file `pg11.epub`) could
  /// not be found by "wonderland", while "download" matched every file in
  /// the Download folder. Call during build: it watches the titles.
  List<PdfEntry> _filterBooks(List<PdfEntry> books, String query) {
    if (query.isEmpty) {
      return books;
    }
    return books
        .where((entry) {
          final title =
              ref.watch(documentTitleProvider(entry.filePath)).valueOrNull ??
              prettyFileTitle(entry.fileName);
          return title.toLowerCase().contains(query) ||
              entry.fileName.toLowerCase().contains(query);
        })
        .toList(growable: false);
  }

  Widget _buildBookTile({required PdfEntry entry}) {
    // Perf (BK-10): scope the queue watch to this tile — only this entry's
    // updates rebuild it (PdfEntry instances are replaced on update, so the
    // select's identity comparison is exact).
    return Consumer(
      builder: (context, tileRef, _) {
        final processedEntry = tileRef.watch(
          preprocessingQueueProvider.select((m) => m[entry.filePath]),
        );
        final displayEntry = processedEntry ?? entry;

        final bookmark = tileRef.watch(
          bookmarkStoreProvider.select((s) => s.valueOrNull?[entry.filePath]),
        );
        final range = bookmark?.readingRange;
        double readingProgress = 0.0;
        var finished = false;
        String? rangeLabel;

        if (range != null) {
          final rangeStart = range.resolvedStartWordIndex;
          final rangeEnd = range.resolvedEndWordIndex;
          final rangeSize = rangeEnd - rangeStart + 1;
          if (rangeSize > 0 && bookmark != null) {
            readingProgress = ((bookmark.wordIndex - rangeStart) / rangeSize)
                .clamp(0.0, 1.0);
          }
          rangeLabel = 'Pages ${range.startPage + 1}-${range.endPage + 1}';
        } else {
          // Documents are no longer retained in queue state, so progress
          // comes from the cross-source progress store. (Not only when a
          // bookmark exists: a finished book keeps its check either way.)
          final record = tileRef
              .read(readingProgressProvider.notifier)
              .getRecord(entry.filePath);
          if (record != null && record.totalWords > 0) {
            readingProgress = record.percent;
            finished = record.finished;
          }
        }

        return _BookTile(
          entry: displayEntry,
          progress: readingProgress,
          finished: finished,
          rangeLabel: rangeLabel,
          divider: false,
          onTap: displayEntry.status == PdfStatus.ready
              ? () => _onBookTap(entry)
              : null,
          onLongPress: displayEntry.status == PdfStatus.ready
              ? () => _onBookLongPress(entry)
              : null,
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header
// ─────────────────────────────────────────────────────────────────────────────

class _LibraryHeader extends ConsumerWidget {
  const _LibraryHeader({
    required this.failedCount,
    required this.titleCount,
    required this.isSearchOpen,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.onSearchToggle,
  });

  final int failedCount;
  final int titleCount;
  final bool isSearchOpen;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onSearchToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RunThruScreenHeader(
            title: 'Library',
            subtitle: titleCount == 0
                ? 'Add something to read'
                : '$titleCount ${titleCount == 1 ? 'title' : 'titles'} on this device',
            actions: [
              if (failedCount > 0) _ErrorBadge(count: failedCount),
              RunThruHeaderIconButton(
                icon: isSearchOpen ? Icons.close_rounded : Icons.search_rounded,
                tooltip: isSearchOpen ? 'Close search' : 'Search',
                onPressed: onSearchToggle,
              ),
              const SizedBox(width: 8),
              RunThruHeaderIconButton(
                icon: Icons.cloud_outlined,
                tooltip: 'Sources',
                onPressed: () => context.go('/sources'),
              ),
            ],
          ),
          if (isSearchOpen) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _LibrarySearchField(
                initialValue: searchQuery,
                onChanged: onSearchChanged,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LibrarySearchField extends StatelessWidget {
  const _LibrarySearchField({
    required this.initialValue,
    required this.onChanged,
  });

  final String initialValue;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      textField: true,
      label: 'Search library',
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: RunThruDecorations.designerInset(borderRadius: 14),
        child: Row(
          children: [
            const Icon(
              Icons.search_rounded,
              size: 19,
              color: RunThruTokens.shellTextSecondary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                initialValue: initialValue,
                autofocus: true,
                onChanged: onChanged,
                textInputAction: TextInputAction.search,
                style: RunThruTypography.body.copyWith(
                  color: RunThruTokens.shellTextPrimary,
                ),
                decoration: InputDecoration(
                  hintText: 'Search books and articles',
                  hintStyle: RunThruTypography.body.copyWith(
                    color: RunThruTokens.shellTextSecondary,
                  ),
                  border: InputBorder.none,
                  isCollapsed: true,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Continue Reading shelf
// ─────────────────────────────────────────────────────────────────────────────

class _ContinueReadingShelf extends StatelessWidget {
  const _ContinueReadingShelf({
    required this.items,
    required this.onItemTap,
    required this.wpm,
    this.hasTitles = false,
    this.continueTargetKey,
  });

  final List<ProgressRecord> items;

  /// The reader's speed, for the time left on each item.
  final int wpm;

  /// Rows shown under the latest book's card.
  static const int maxRowsAfterLatest = 3;

  /// Whether the library already holds something to read.
  final bool hasTitles;
  final void Function(ProgressRecord) onItemTap;
  final GlobalKey? continueTargetKey;

  @override
  Widget build(BuildContext context) {
    final leading = items.isEmpty ? null : items.first;
    // The latest book and a few more. Listing everything in progress turned
    // this into a second copy of the library and pushed the shelves off the
    // first screen; the rest are on their shelves, with their rings.
    final rest = items.length <= 1
        ? const <ProgressRecord>[]
        : items.skip(1).take(maxRowsAfterLatest).toList(growable: false);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(title: 'Continue reading', topPadding: 0),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(18, 22, 18, 20),
                decoration: RunThruDecorations.designerFlat(borderRadius: 18),
                child: Column(
                  children: [
                    const RunThruMark(size: 50),
                    const SizedBox(height: 12),
                    const Text(
                      'Nothing in progress yet',
                      style: RunThruTypography.rowTitle,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      // With books already here, "Add a source" was the
                      // wrong next step.
                      hasTitles
                          ? 'Pick something below to start reading.'
                          : 'Add a source to start your first reading '
                                'session.',
                      style: RunThruTypography.metadata,
                      textAlign: TextAlign.center,
                    ),
                    if (!hasTitles) ...[
                      const SizedBox(height: 16),
                      RunThruPrimaryButton(
                        icon: Icons.add_link_rounded,
                        label: 'Add a source',
                        onPressed: () => context.go('/sources'),
                      ),
                    ],
                  ],
                ),
              ),
            )
          else ...[
            _ContinueHero(
              targetKey: continueTargetKey,
              item: leading!,
              wpm: wpm,
              onTap: () => onItemTap(leading),
            ),
            if (rest.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Container(
                  decoration: RunThruDecorations.designerFlat(borderRadius: 16),
                  child: Column(
                    children: [
                      for (final item in rest)
                        _ShelfCard(
                          item: item,
                          wpm: wpm,
                          onTap: () => onItemTap(item),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _ContinueHero extends StatelessWidget {
  const _ContinueHero({
    required this.item,
    required this.wpm,
    required this.onTap,
    this.targetKey,
  });

  final ProgressRecord item;
  final int wpm;
  final VoidCallback onTap;
  final GlobalKey? targetKey;

  @override
  Widget build(BuildContext context) {
    final percent = item.displayPercent;
    final minutesLeft = formatTimeLeft(item.minutesLeftAt(wpm));
    final source = _SourceBadge._label(item.source);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
      // One announcement, with the visible source name and time left.
      child: Semantics(
        label:
            'Continue reading ${item.title}, $source, $percent percent read, '
            '$minutesLeft',
        button: true,
        excludeSemantics: true,
        onTap: onTap,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            key: targetKey,
            padding: const EdgeInsets.all(16),
            decoration: RunThruDecorations.designerRaised(borderRadius: 20),
            child: Row(
              children: [
                RunThruIconThumb(icon: _iconForSource(item.source), size: 50),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: RunThruTypography.rowTitle.copyWith(
                          fontSize: 18,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$source · $minutesLeft',
                        style: RunThruTypography.metadata,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                RunThruProgressRing(value: item.percent),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ShelfCard extends StatefulWidget {
  const _ShelfCard({
    required this.item,
    required this.wpm,
    required this.onTap,
  });

  final ProgressRecord item;
  final int wpm;
  final VoidCallback onTap;

  @override
  State<_ShelfCard> createState() => _ShelfCardState();
}

class _ShelfCardState extends State<_ShelfCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final percent = widget.item.displayPercent;
    // The ring already gives the percentage; the line under the title says
    // what is left, as the leading card does.
    final minutesLeft = formatTimeLeft(widget.item.minutesLeftAt(widget.wpm));

    final source = _SourceBadge._label(widget.item.source);
    // One announcement with the visible source name; the row's own text is
    // excluded so it is not read again.
    return Semantics(
      label:
          '${widget.item.title}, $source, $percent percent read, '
          '$minutesLeft',
      button: true,
      excludeSemantics: true,
      onTap: widget.onTap,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: Opacity(
          opacity: _pressed ? 0.82 : 1,
          child: RunThruShellRow(
            title: widget.item.title,
            metadata: '$source · $minutesLeft',
            icon: _iconForSource(widget.item.source),
            trailing: RunThruProgressRing(value: widget.item.percent, size: 42),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Filter chips
// ─────────────────────────────────────────────────────────────────────────────

class _FilterChipRow extends StatelessWidget {
  const _FilterChipRow({required this.selected, required this.onChanged});

  final _LibraryFilter selected;
  final void Function(_LibraryFilter) onChanged;

  static const _labels = {
    _LibraryFilter.all: 'All',
    _LibraryFilter.books: 'Books',
    _LibraryFilter.articles: 'Articles',
  };

  @override
  Widget build(BuildContext context) {
    return RunThruSegmentedFilter<_LibraryFilter>(
      values: _LibraryFilter.values,
      selected: selected,
      labelFor: (filter) => _labels[filter]!,
      onChanged: onChanged,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section header
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.topPadding = 20});

  final String title;
  final double topPadding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, topPadding, 20, 10),
      child: Text(title, style: RunThruTypography.sectionLabel),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Library section cards
// ─────────────────────────────────────────────────────────────────────────────

class _LibrarySection extends StatelessWidget {
  const _LibrarySection({
    required this.title,
    required this.countLabel,
    required this.dotColor,
    required this.itemCount,
    this.itemBuilder,
    this.empty,
    this.headerAction,
    this.liveCount = false,
  });

  final String title;
  final String countLabel;
  final Color dotColor;
  final int itemCount;
  final IndexedWidgetBuilder? itemBuilder;
  final Widget? empty;

  /// A control at the end of the header (a 48dp target). The header gives
  /// up its own padding to it, so the title sits where it does without one.
  final Widget? headerAction;

  /// Whether the count changes while the section is on screen ("Loading",
  /// "Updating…", "12 articles") and should be announced when it does.
  final bool liveCount;

  @override
  Widget build(BuildContext context) {
    final action = headerAction;
    return NeumorphicCard(
      surface: RunThruSurface.shell,
      size: RunThruShadowSize.standard,
      borderRadius: 16,
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      // A paged section ends in its page indicator, a full tap target that
      // stands in for the bottom padding.
      padding: EdgeInsets.fromLTRB(
        15,
        action == null ? 15 : 1,
        15,
        itemBuilder != null && itemCount > _kTilesPerPage ? 0 : 14,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(3, 0, 3, action == null ? 11 : 0),
            child: Row(
              children: [
                ExcludeSemantics(
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: dotColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                const SizedBox(width: 9),
                Semantics(
                  header: true,
                  child: Text(title, style: RunThruTypography.sectionLabel),
                ),
                const Spacer(),
                Semantics(
                  liveRegion: liveCount,
                  child: Text(
                    countLabel,
                    style: RunThruTypography.caption.copyWith(
                      color: RunThruTokens.shellInkSoft,
                    ),
                  ),
                ),
                if (action != null) action,
              ],
            ),
          ),
          if (itemCount == 0 || itemBuilder == null)
            _SectionWell(child: empty ?? const SizedBox.shrink())
          else
            PagedTileWell(
              label: title,
              itemCount: itemCount,
              tilesPerPage: _kTilesPerPage,
              itemBuilder: (context, index) =>
                  _FloatingTile(child: itemBuilder!(context, index)),
            ),
        ],
      ),
    );
  }
}

class _SectionWell extends StatelessWidget {
  const _SectionWell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return NeumorphicCard(
      surface: RunThruSurface.shell,
      inset: true,
      size: RunThruShadowSize.small,
      borderRadius: 12,
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: child,
    );
  }
}

class _FloatingTile extends StatelessWidget {
  const _FloatingTile({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return NeumorphicCard(
      surface: RunThruSurface.shell,
      size: RunThruShadowSize.small,
      borderRadius: 13,
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.symmetric(horizontal: 13),
      child: child,
    );
  }
}

class _BookTile extends StatefulWidget {
  const _BookTile({
    required this.entry,
    required this.progress,
    required this.onTap,
    required this.onLongPress,
    required this.divider,
    this.finished = false,
    this.rangeLabel,
  });

  final PdfEntry entry;
  final double progress;

  /// Whether the book was read to the end.
  final bool finished;
  final String? rangeLabel;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool divider;

  @override
  State<_BookTile> createState() => _BookTileState();
}

class _BookTileState extends State<_BookTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final statusTone = _statusTone(widget.entry.status);

    return Consumer(
      builder: (context, ref, _) {
        final path = widget.entry.filePath;
        final info = ref.watch(documentInfoProvider(path)).valueOrNull;
        final title = info?.title ?? prettyFileTitle(widget.entry.fileName);
        final words = ref.watch(documentWordCountProvider(path)).valueOrNull;
        final wpm = ref.watch(
          configProvider.select((c) => c.valueOrNull?.defaultWpm),
        );
        final time = widget.rangeLabel == null
            ? bookRowTime(widget.entry, words: words, wpm: wpm)
            : null;
        final detail =
            widget.rangeLabel ??
            bookRowDetail(widget.entry, author: info?.author, time: time);
        return _buildTile(
          title,
          detail,
          // With an author, the time is its own piece: the name is
          // shortened before the time is.
          time != null && detail != time ? time : null,
          statusTone,
        );
      },
    );
  }

  /// How long the book takes at the reader's speed ("1 h 52 min"), once
  /// its length is known.
  @visibleForTesting
  static String? bookRowTime(PdfEntry entry, {int? words, int? wpm}) {
    if (entry.status != PdfStatus.ready) return null;
    if (words == null || words <= 0 || wpm == null || wpm <= 0) return null;
    return formatMinutes((words / wpm).ceil());
  }

  /// The line under a book's title: who wrote it, or failing that how long
  /// it takes to read; while the file is not ready, its state instead.
  /// With both an author and a [time], the time is shown after this.
  @visibleForTesting
  static String bookRowDetail(PdfEntry entry, {String? author, String? time}) {
    if (entry.status != PdfStatus.ready) return _statusLabel(entry);
    final name = author?.trim() ?? '';
    if (name.isNotEmpty) return name;
    return time ?? _statusLabel(entry);
  }

  Widget _buildTile(
    String title,
    String detail,
    String? time,
    RunThruStatusTone statusTone,
  ) {
    // One announcement: the row's own text is excluded so TalkBack does not
    // read the title three times.
    return Semantics(
      label: time == null ? '$title, $detail' : '$title, $detail, $time',
      button: widget.onTap != null,
      excludeSemantics: true,
      // Excluding the row's own semantics drops its gesture actions, so the
      // label node carries them for TalkBack / VoiceOver.
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: GestureDetector(
        onTapDown: widget.onTap == null
            ? null
            : (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: widget.onTap == null
            ? null
            : (_) => setState(() => _pressed = false),
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: Opacity(
          opacity: _pressed ? 0.82 : 1,
          child: RunThruShellRow(
            title: title,
            metadata: detail,
            metadataSuffix: time,
            icon: Icons.menu_book_rounded,
            divider: widget.divider,
            trailing: widget.progress > 0 || widget.finished
                ? RunThruProgressRing(
                    value: widget.progress,
                    finished: widget.finished,
                    size: 42,
                  )
                : RunThruStatusPill(
                    label: _statusPillLabel(widget.entry.status),
                    tone: statusTone,
                  ),
          ),
        ),
      ),
    );
  }

  static RunThruStatusTone _statusTone(PdfStatus status) {
    return switch (status) {
      PdfStatus.ready => RunThruStatusTone.ready,
      PdfStatus.processing || PdfStatus.preview => RunThruStatusTone.warning,
      PdfStatus.error ||
      PdfStatus.unsupported ||
      PdfStatus.permanentlyFailed => RunThruStatusTone.error,
      PdfStatus.pending || PdfStatus.queued => RunThruStatusTone.neutral,
    };
  }

  static String _statusPillLabel(PdfStatus status) => switch (status) {
    PdfStatus.ready => 'Ready',
    PdfStatus.processing || PdfStatus.preview => 'Preparing',
    PdfStatus.error ||
    PdfStatus.unsupported ||
    PdfStatus.permanentlyFailed => 'Issue',
    PdfStatus.pending || PdfStatus.queued => 'Pending',
  };

  static String _statusLabel(PdfEntry entry) {
    return switch (entry.status) {
      PdfStatus.ready => 'Local file',
      PdfStatus.processing => 'Preparing...',
      PdfStatus.preview => 'Preview ready',
      PdfStatus.error =>
        'Error (retry ${entry.retryCount}/${PdfEntry.maxRetries})',
      PdfStatus.unsupported => 'Not supported',
      PdfStatus.permanentlyFailed => 'Failed',
      PdfStatus.pending || PdfStatus.queued => 'Pending',
    };
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty states
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyBooksState extends StatelessWidget {
  const _EmptyBooksState({this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Text(
        message ?? 'No books yet. Add a PDF or EPUB from Sources.',
        style: RunThruTypography.caption.copyWith(
          color: RunThruTokens.shellTextSecondary,
        ),
      ),
    );
  }
}

class _EmptyArticlesState extends StatelessWidget {
  const _EmptyArticlesState({this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
        child: Text(
          message ??
              'No articles yet. Connect Instapaper in Sources, or share a link to RunThru.',
          style: RunThruTypography.caption.copyWith(
            color: RunThruTokens.shellTextSecondary,
          ),
        ),
      ),
    );
  }
}

/// Shown in the Articles section when the Instapaper connection is in an
/// error state (the connection was refused, secure storage failed).
/// Tapping opens the sign-in sheet.
class _ArticlesAuthErrorTile extends ConsumerWidget {
  const _ArticlesAuthErrorTile({required this.message});

  final String message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Semantics(
      liveRegion: true,
      button: true,
      child: InkWell(
        onTap: () => showInstapaperSignIn(context, ref),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Row(
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  size: 16,
                  color: RunThruTokens.shellError,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$message Tap to reconnect.',
                    style: RunThruTypography.caption.copyWith(
                      color: RunThruTokens.shellError,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A section's list could not be loaded and there is none to fall back on
/// (the articles, or the books): what happened in a sentence, and a way to
/// try again.
class _ArticlesLoadError extends StatelessWidget {
  const _ArticlesLoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 8, 0),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: Text(
                message,
                style: RunThruTypography.caption.copyWith(
                  color: RunThruTokens.shellError,
                ),
              ),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(
              minimumSize: const Size(48, 48),
              foregroundColor: RunThruTokens.shellAccent,
            ),
            child: Text(
              'Try again',
              style: RunThruTypography.caption.copyWith(
                color: RunThruTokens.shellAccent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fetches the Instapaper list again. A 48dp target at the end of the
/// Articles header; its icon lines up with the header's right edge.
class _RefreshArticlesButton extends StatelessWidget {
  const _RefreshArticlesButton({required this.onRefresh});

  /// Null while a fetch is already running.
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onRefresh,
      tooltip: 'Refresh articles',
      padding: EdgeInsets.zero,
      alignment: Alignment.centerRight,
      constraints: const BoxConstraints.tightFor(width: 48, height: 48),
      icon: const Icon(Icons.refresh_rounded, size: 18),
      color: RunThruTokens.shellInkSoft,
      disabledColor: RunThruTokens.shellInkSoft.withValues(alpha: 0.4),
    );
  }
}

class _ArticlesSliverList extends ConsumerWidget {
  const _ArticlesSliverList({required this.query});

  final String query;

  Widget _section({
    required String countLabel,
    Widget? empty,
    int itemCount = 0,
    IndexedWidgetBuilder? itemBuilder,
    Widget? headerAction,
  }) {
    return SliverToBoxAdapter(
      child: _LibrarySection(
        title: 'Articles',
        countLabel: countLabel,
        dotColor: RunThruTokens.shellTealDeep,
        itemCount: itemCount,
        itemBuilder: itemBuilder,
        empty: empty,
        headerAction: headerAction,
        liveCount: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A build that cannot connect to Instapaper does not suggest it.
    if (!ref.watch(instapaperAvailableProvider)) {
      return _section(
        countLabel: '0 articles',
        empty: _EmptyArticlesState(
          message: query.isEmpty
              ? 'No articles yet. Share a link to RunThru to read it.'
              : 'No articles match this search.',
        ),
      );
    }

    final authState = ref.watch(instapaperAuthProvider);

    // Surface the real connection state instead of masking errors as an empty
    // list — otherwise a failed/expired connection just reads as "no articles".
    switch (authState) {
      case InstapaperAuthChecking():
      case InstapaperAuthLoading():
        return _section(countLabel: 'Loading', empty: const _SectionLoading());
      case InstapaperAuthUnauthenticated():
      case InstapaperAuthLegacyFallbackRequired():
        return _section(
          countLabel: '0 articles',
          empty: _EmptyArticlesState(
            message: query.isEmpty ? null : 'No articles match this search.',
          ),
        );
      case InstapaperAuthError(:final message):
        return _section(
          countLabel: 'Issue',
          empty: _ArticlesAuthErrorTile(message: message),
        );
      case InstapaperAuthAuthenticated():
        break;
    }

    final list = ref.watch(instapaperBookmarksProvider);
    final bookmarks = list.valueOrNull ?? const <InstapaperBookmark>[];

    Future<void> refresh() async {
      final messenger = ScaffoldMessenger.of(context);
      final problem = await ref
          .read(instapaperBookmarksProvider.notifier)
          .refresh();
      if (problem == null) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(problem)));
    }

    // The first fetch, or a fetch for a newly connected account: there is
    // no list of this account's to show yet.
    if (list.isLoading && !list.isRefreshing) {
      return _section(countLabel: 'Loading', empty: const _SectionLoading());
    }
    // Nothing loaded and the last fetch failed. (A failed refresh of a
    // list that is there leaves the list.)
    if (list.hasError && bookmarks.isEmpty) {
      return _section(
        countLabel: 'Issue',
        empty: _ArticlesLoadError(
          message: instapaperListFailureMessage(list.error!),
          onRetry: refresh,
        ),
      );
    }

    final refreshButton = _RefreshArticlesButton(
      onRefresh: list.isLoading ? null : refresh,
    );
    final visible = query.isEmpty
        ? bookmarks
        : bookmarks
              .where(
                (b) => '${b.title} ${b.domain} ${b.description} ${b.url}'
                    .toLowerCase()
                    .contains(query),
              )
              .toList(growable: false);
    final countLabel = list.isLoading
        ? 'Updating…'
        : _countLabel(visible.length, 'article');

    if (visible.isEmpty) {
      return _section(
        countLabel: countLabel,
        headerAction: refreshButton,
        empty: _EmptyArticlesState(
          message: query.isEmpty
              ? 'Nothing unread in Instapaper. Articles you save there show up here.'
              : 'No articles match this search.',
        ),
      );
    }

    // Rebuild when a position is saved; times are at the reader's speed.
    ref.watch(readingProgressProvider);
    final progressStore = ref.read(readingProgressProvider.notifier);
    final wpm =
        ref.watch(configProvider.select((c) => c.valueOrNull?.defaultWpm)) ??
        const AppConfig().defaultWpm;
    final opening = ref.watch(
      instapaperArticleImportProvider.select(
        (s) => s is ArticleImportLoading ? s.bookmarkId : null,
      ),
    );

    return _section(
      countLabel: countLabel,
      headerAction: refreshButton,
      itemCount: visible.length,
      itemBuilder: (context, index) {
        final bookmark = visible[index];
        final details = articleRowDetails(
          bookmark,
          record: progressStore.getRecord(
            'instapaper://${bookmark.bookmarkId}',
          ),
          wpm: wpm,
        );
        return _ArticleRow(
          title: bookmark.displayTitle,
          details: details,
          opening: opening == bookmark.bookmarkId,
          // One article at a time.
          onTap: opening != null
              ? null
              : () => ref
                    .read(instapaperArticleImportProvider.notifier)
                    .importArticle(bookmark),
        );
      },
    );
  }
}

/// What an article's row says besides its title.
@immutable
class ArticleRowDetails {
  /// Creates row details.
  const ArticleRowDetails({
    required this.source,
    required this.progress,
    this.time,
    this.finished = false,
  });

  /// Where the article is from: its site, or "Instapaper" when it has none.
  final String source;

  /// How long the article takes at the reader's speed, once its length is
  /// known (after it has been opened on this device).
  final String? time;

  /// How far it has been read, 0 to 1.
  final double progress;

  /// Whether it was read to the end on this device.
  final bool finished;

  /// Whether nobody has started it.
  bool get unread => progress <= 0 && !finished;
}

/// Works out an article row from what is actually known: the bookmark from
/// Instapaper and, once the article has been opened here, this device's
/// record of it. (The row used to show a reading time made up from the
/// bookmark's description: "6 min" for almost everything.)
@visibleForTesting
ArticleRowDetails articleRowDetails(
  InstapaperBookmark bookmark, {
  ProgressRecord? record,
  required int wpm,
}) {
  final words = record?.totalWords ?? 0;
  // Whichever position is newer: this device's, or the one Instapaper has
  // from another.
  final localIsNewer =
      record != null &&
      words > 0 &&
      record.lastReadAt.millisecondsSinceEpoch ~/ 1000 >=
          bookmark.progressTimestamp;
  return ArticleRowDetails(
    source: bookmark.domain.isEmpty ? 'Instapaper' : bookmark.domain,
    time: words > 0 && wpm > 0 ? formatMinutes((words / wpm).ceil()) : null,
    progress: (localIsNewer ? record.percent : bookmark.progress).clamp(
      0.0,
      1.0,
    ),
    finished: localIsNewer && record.finished,
  );
}

class _ArticleRow extends StatelessWidget {
  const _ArticleRow({
    required this.title,
    required this.details,
    required this.opening,
    required this.onTap,
  });

  final String title;
  final ArticleRowDetails details;

  /// Whether this article is being fetched right now.
  final bool opening;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final time = details.time;
    final spoken = [
      title,
      if (opening) 'opening' else if (details.unread) 'unread',
      details.source,
      if (time != null) time,
      if (!opening && !details.unread && !details.finished)
        '${(details.progress * 100).round()} percent read',
    ].join(', ');
    // One announcement for the row, as for books: its own text is excluded
    // so the title is not read twice.
    return Semantics(
      label: spoken,
      button: true,
      enabled: onTap != null,
      liveRegion: opening,
      excludeSemantics: true,
      onTap: onTap,
      child: RunThruShellRow(
        title: title,
        metadata: details.source,
        metadataSuffix: time,
        icon: _iconForSource('instapaper'),
        onTap: onTap,
        trailing: opening
            ? const RunThruStatusPill(
                label: 'Opening…',
                tone: RunThruStatusTone.warning,
              )
            : details.unread
            ? const RunThruStatusPill(
                label: 'New',
                tone: RunThruStatusTone.ready,
              )
            : RunThruProgressRing(
                value: details.progress,
                finished: details.finished,
                size: 42,
              ),
      ),
    );
  }
}

class _SectionLoading extends StatelessWidget {
  const _SectionLoading();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Text(
        'Loading…',
        style: RunThruTypography.caption.copyWith(
          color: RunThruTokens.shellTextSecondary,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Source badge
// ─────────────────────────────────────────────────────────────────────────────

String _countLabel(int count, String singular) {
  if (count == 1) return '1 $singular';
  return '$count ${singular}s';
}

IconData _iconForSource(String source) => switch (source) {
  'instapaper' => Icons.bookmark_rounded,
  'drive' => Icons.cloud_outlined,
  'substack' => Icons.mail_outline_rounded,
  'sample' => Icons.auto_stories_rounded,
  _ => Icons.book_rounded,
};

Color _sourceColor(String source) => switch (source) {
  'instapaper' => RunThruTokens.shellAccent,
  'drive' => RunThruTokens.shellReady,
  'substack' => RunThruTokens.shellProcessing,
  _ => RunThruTokens.shellTextSecondary,
};

/// Small pill badge showing the content source (Instapaper, Local, etc.).
class _SourceBadge extends StatelessWidget {
  const _SourceBadge({required this.source});

  final String source;

  static String _label(String source) => switch (source) {
    'instapaper' => 'Instapaper',
    'drive' => 'Drive',
    'substack' => 'Substack',
    'sample' => 'Sample',
    _ => 'Local',
  };

  @override
  Widget build(BuildContext context) {
    final color = _sourceColor(source);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.18), width: 0.5),
      ),
      child: Text(
        _label(source),
        style: RunThruTypography.caption.copyWith(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Error badge
// ─────────────────────────────────────────────────────────────────────────────

/// Small badge showing count of permanently failed files.
class _ErrorBadge extends StatelessWidget {
  const _ErrorBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: RunThruTokens.shellError,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count failed',
        style: RunThruTypography.caption.copyWith(
          color: RunThruTokens.shellOnError,
        ),
      ),
    );
  }
}
