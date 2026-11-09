import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:runthru/design/design.dart';
import 'package:runthru/features/content/providers/google_drive_files_provider.dart';
import 'package:runthru/features/content/providers/instapaper_auth_provider.dart';
import 'package:runthru/features/content/providers/instapaper_bookmarks_provider.dart';
import 'package:runthru/features/content/services/google_drive_client.dart';
import 'package:runthru/features/reading/providers/reading_progress_provider.dart';
import 'package:runthru/core/sample_document.dart';
import 'package:runthru/services/folder_scanner.dart';
import 'package:runthru/services/models.dart';
import 'package:runthru/services/preprocessing_queue.dart';
import 'package:runthru/store/bookmark_store.dart';
import 'package:runthru/store/config.dart';
import 'package:runthru/widgets/neumorphic_card.dart';
import 'package:runthru/widgets/reading_goal_onboarding_gate.dart';
import 'package:runthru/widgets/runthru_shell_widgets.dart';

/// Content-type filter for the unified library.
enum _LibraryFilter { all, books, articles, docs }

const int _kTilesPerPage = 4;
const double _kPagedWellHeight = 340;

/// Unified library screen: Continue Reading → Books → Articles.
///
/// Organised by reading intent and content type. Source is metadata, not
/// the primary navigation structure.
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  _LibraryFilter _filter = _LibraryFilter.all;
  bool _isSearchOpen = false;
  String _searchQuery = '';
  bool _sampleSeeded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _seedSampleIfNeeded();
    });
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
    final shelf = activePaths == null
        ? rawShelf
        : rawShelf
              .where(
                (r) => r.source != 'local' || activePaths.contains(r.contentId),
              )
              .toList();
    final authState = ref.watch(instapaperAuthProvider);
    final sourceCount = 1 + (authState is InstapaperAuthAuthenticated ? 1 : 0);
    final normalizedSearchQuery = _searchQuery.trim().toLowerCase();

    // Navigate to reader on successful Instapaper article import.
    ref.listen<ArticleImportState>(instapaperArticleImportProvider, (
      previous,
      next,
    ) {
      if (next is ArticleImportDone) {
        ref.read(instapaperArticleImportProvider.notifier).clear();
        context.push(
          '/read-instapaper',
          extra: {
            'document': next.document,
            'title': next.title,
            'bookmarkId': next.bookmarkId,
            'initialProgress': next.initialProgress,
          },
        );
      } else if (next is ArticleImportError) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(next.message)));
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
                sourceCount: sourceCount,
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
            SliverToBoxAdapter(
              child: _ContinueReadingShelf(
                items: shelf,
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
                    empty: _SectionError(message: e.toString()),
                  ),
                ),
              ),
            ],

            // ── Articles section ──
            if (_filter == _LibraryFilter.all ||
                _filter == _LibraryFilter.articles) ...[
              _ArticlesSliverList(query: normalizedSearchQuery),
            ],

            // ── Docs section ──
            if (_filter == _LibraryFilter.all ||
                _filter == _LibraryFilter.docs) ...[
              const SliverToBoxAdapter(
                child: _LibrarySection(
                  title: 'Docs',
                  countLabel: '0 docs',
                  dotColor: RunThruTokens.shellInkSoft,
                  itemCount: 0,
                  empty: _EmptyDocsState(),
                ),
              ),
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
  /// the last word position. Shows a hint if the bookmark list isn't loaded.
  void _resumeInstapaperItem(ProgressRecord item) {
    final bookmarkId = int.tryParse(
      item.contentId.replaceFirst('instapaper://', ''),
    );
    final bookmarks = ref.read(instapaperBookmarksProvider).valueOrNull;
    final bookmark = bookmarks
        ?.where((b) => b.bookmarkId == bookmarkId)
        .firstOrNull;

    if (bookmark == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Open this article from the Articles list to resume.'),
        ),
      );
      return;
    }

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

  static List<PdfEntry> _filterBooks(List<PdfEntry> books, String query) {
    if (query.isEmpty) {
      return books;
    }
    return books
        .where((entry) {
          return entry.fileName.toLowerCase().contains(query) ||
              entry.filePath.toLowerCase().contains(query);
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
        } else if (bookmark != null) {
          // Documents are no longer retained in queue state, so word totals
          // come from the cross-source progress store instead.
          final record = tileRef
              .read(readingProgressProvider.notifier)
              .getRecord(entry.filePath);
          if (record != null && record.totalWords > 0) {
            readingProgress = record.percent;
          }
        }

        return _BookTile(
          entry: displayEntry,
          progress: readingProgress,
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
    required this.sourceCount,
    required this.isSearchOpen,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.onSearchToggle,
  });

  final int failedCount;
  final int sourceCount;
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
            subtitle:
                'Synced just now · $sourceCount ${sourceCount == 1 ? 'source' : 'sources'}',
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
    this.continueTargetKey,
  });

  final List<ProgressRecord> items;
  final void Function(ProgressRecord) onItemTap;
  final GlobalKey? continueTargetKey;

  @override
  Widget build(BuildContext context) {
    final leading = items.isEmpty ? null : items.first;
    final rest = items.length <= 1
        ? const <ProgressRecord>[]
        : items.skip(1).toList(growable: false);
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
                    const Text(
                      'Add a source to start your first reading session.',
                      style: RunThruTypography.metadata,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    RunThruPrimaryButton(
                      icon: Icons.add_link_rounded,
                      label: 'Add a source',
                      onPressed: () => context.go('/sources'),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            _ContinueHero(
              targetKey: continueTargetKey,
              item: leading!,
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
                        _ShelfCard(item: item, onTap: () => onItemTap(item)),
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
    required this.onTap,
    this.targetKey,
  });

  final ProgressRecord item;
  final VoidCallback onTap;
  final GlobalKey? targetKey;

  @override
  Widget build(BuildContext context) {
    final percent = (item.percent * 100).round();
    final minutesLeft = item.minutesLeft <= 1
        ? '<1 min left'
        : '${item.minutesLeft} min left';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
      child: Semantics(
        label: '${item.title}, ${item.source}, $percent percent read',
        button: true,
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
                        '${_SourceBadge._label(item.source)} · $minutesLeft',
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
  const _ShelfCard({required this.item, required this.onTap});

  final ProgressRecord item;
  final VoidCallback onTap;

  @override
  State<_ShelfCard> createState() => _ShelfCardState();
}

class _ShelfCardState extends State<_ShelfCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final percent = (widget.item.percent * 100).round();

    return Semantics(
      label:
          '${widget.item.title}, ${widget.item.source}, $percent percent read',
      button: true,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: Opacity(
          opacity: _pressed ? 0.82 : 1,
          child: RunThruShellRow(
            title: widget.item.title,
            metadata: '${_SourceBadge._label(widget.item.source)} · $percent%',
            icon: _iconForSource(widget.item.source),
            trailing: RunThruProgressRing(value: widget.item.percent, size: 42),
            semanticLabel:
                '${widget.item.title}, ${widget.item.source}, $percent percent read',
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
    _LibraryFilter.docs: 'Docs',
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
  });

  final String title;
  final String countLabel;
  final Color dotColor;
  final int itemCount;
  final IndexedWidgetBuilder? itemBuilder;
  final Widget? empty;

  @override
  Widget build(BuildContext context) {
    return NeumorphicCard(
      surface: RunThruSurface.shell,
      size: RunThruShadowSize.standard,
      borderRadius: 16,
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      padding: const EdgeInsets.fromLTRB(15, 15, 15, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(3, 0, 3, 11),
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
                Text(
                  countLabel,
                  style: RunThruTypography.caption.copyWith(
                    color: RunThruTokens.shellInkSoft,
                  ),
                ),
              ],
            ),
          ),
          if (itemCount == 0 || itemBuilder == null)
            _SectionWell(child: empty ?? const SizedBox.shrink())
          else
            _PagedWell(itemCount: itemCount, itemBuilder: itemBuilder!),
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

class _PagedWell extends StatefulWidget {
  const _PagedWell({required this.itemCount, required this.itemBuilder});

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  @override
  State<_PagedWell> createState() => _PagedWellState();
}

class _PagedWellState extends State<_PagedWell> {
  late final PageController _controller;
  int _page = 0;

  int get _pageCount => (widget.itemCount / _kTilesPerPage).ceil();

  @override
  void initState() {
    super.initState();
    _controller = PageController();
  }

  @override
  void didUpdateWidget(covariant _PagedWell oldWidget) {
    super.didUpdateWidget(oldWidget);
    final maxPage = (_pageCount - 1).clamp(0, _pageCount);
    if (_page > maxPage) {
      _page = maxPage;
      _controller.jumpToPage(_page);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goToPage(int page) {
    final target = page.clamp(0, _pageCount - 1);
    setState(() => _page = target);
    if (isReducedMotion(context)) {
      _controller.jumpToPage(target);
    } else {
      _controller.animateToPage(
        target,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _SectionWell(
          child: SizedBox(
            height: _kPagedWellHeight,
            child: PageView.builder(
              controller: _controller,
              itemCount: _pageCount,
              onPageChanged: (page) => setState(() => _page = page),
              itemBuilder: (context, pageIndex) {
                final firstIndex = pageIndex * _kTilesPerPage;
                final pageItemCount = (widget.itemCount - firstIndex).clamp(
                  0,
                  _kTilesPerPage,
                );
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Column(
                    children: [
                      for (var i = 0; i < pageItemCount; i++) ...[
                        _FloatingTile(
                          child: widget.itemBuilder(context, firstIndex + i),
                        ),
                        if (i < pageItemCount - 1) const SizedBox(height: 9),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ),
        if (_pageCount > 1) ...[
          const SizedBox(height: 11),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var index = 0; index < _pageCount; index++) ...[
                _PageDot(
                  index: index,
                  selected: index == _page,
                  total: _pageCount,
                  onTap: () => _goToPage(index),
                ),
                if (index < _pageCount - 1) const SizedBox(width: 6),
              ],
            ],
          ),
        ],
      ],
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

class _PageDot extends StatelessWidget {
  const _PageDot({
    required this.index,
    required this.selected,
    required this.total,
    required this.onTap,
  });

  final int index;
  final bool selected;
  final int total;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: 'Page ${index + 1} of $total',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: isReducedMotion(context)
              ? Duration.zero
              : const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          width: selected ? 17 : 7,
          height: 7,
          decoration: BoxDecoration(
            color: selected
                ? RunThruTokens.shellTeal
                : RunThruTokens.shellInkSoft.withValues(alpha: 0.34),
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ),
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
    this.rangeLabel,
  });

  final PdfEntry entry;
  final double progress;
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

    return Semantics(
      label: '${widget.entry.fileName}, ${_statusLabel(widget.entry)}',
      button: widget.onTap != null,
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
            title: widget.entry.fileName,
            metadata: widget.rangeLabel ?? _statusLabel(widget.entry),
            icon: Icons.menu_book_rounded,
            divider: widget.divider,
            trailing: widget.progress > 0
                ? RunThruProgressRing(value: widget.progress, size: 42)
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
        message ?? 'No books yet. Import a PDF or EPUB from the + menu.',
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
              'No articles yet. Connect Instapaper or paste a URL from the + menu.',
          style: RunThruTypography.caption.copyWith(
            color: RunThruTokens.shellTextSecondary,
          ),
        ),
      ),
    );
  }
}

/// Shown in the Articles section when the Instapaper connection is in an
/// error state (expired tokens, missing API config, secure-storage failure).
/// Tapping opens Sources so the user can reconnect.
class _ArticlesAuthErrorTile extends StatelessWidget {
  const _ArticlesAuthErrorTile({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      button: true,
      child: InkWell(
        onTap: () => context.push('/settings/sources'),
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
    );
  }
}

class _EmptyDocsState extends StatelessWidget {
  const _EmptyDocsState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Text(
        'No docs yet.',
        style: RunThruTypography.caption.copyWith(
          color: RunThruTokens.shellTextSecondary,
        ),
      ),
    );
  }
}

class _ArticlesSliverList extends ConsumerWidget {
  const _ArticlesSliverList({required this.query});

  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(instapaperAuthProvider);

    // Surface the real connection state instead of masking errors as an empty
    // list — otherwise a failed/expired connection just reads as "no articles".
    switch (authState) {
      case InstapaperAuthChecking():
      case InstapaperAuthLoading():
        return const SliverToBoxAdapter(
          child: _LibrarySection(
            title: 'Articles',
            countLabel: 'Loading',
            dotColor: RunThruTokens.shellTealDeep,
            itemCount: 0,
            empty: _SectionLoading(),
          ),
        );
      case InstapaperAuthUnauthenticated():
      case InstapaperAuthLegacyFallbackRequired():
        return const SliverToBoxAdapter(
          child: _LibrarySection(
            title: 'Articles',
            countLabel: '0 articles',
            dotColor: RunThruTokens.shellTealDeep,
            itemCount: 0,
            empty: _EmptyArticlesState(),
          ),
        );
      case InstapaperAuthError(:final message):
        return SliverToBoxAdapter(
          child: _LibrarySection(
            title: 'Articles',
            countLabel: 'Issue',
            dotColor: RunThruTokens.shellTealDeep,
            itemCount: 0,
            empty: _ArticlesAuthErrorTile(message: message),
          ),
        );
      case InstapaperAuthAuthenticated():
        break;
    }

    final bookmarksAsync = ref.watch(instapaperBookmarksProvider);
    return bookmarksAsync.when(
      data: (bookmarks) {
        final visibleBookmarks = query.isEmpty
            ? bookmarks
            : bookmarks
                  .where((bookmark) {
                    final searchableText =
                        '${bookmark.title} ${bookmark.domain} ${bookmark.description} ${bookmark.url}'
                            .toLowerCase();
                    return searchableText.contains(query);
                  })
                  .toList(growable: false);

        if (visibleBookmarks.isEmpty) {
          return SliverToBoxAdapter(
            child: _LibrarySection(
              title: 'Articles',
              countLabel: '0 articles',
              dotColor: RunThruTokens.shellTealDeep,
              itemCount: 0,
              empty: _EmptyArticlesState(
                message: query.isEmpty
                    ? null
                    : 'No articles match this search.',
              ),
            ),
          );
        }
        return SliverToBoxAdapter(
          child: _LibrarySection(
            title: 'Articles',
            countLabel: _countLabel(visibleBookmarks.length, 'article'),
            dotColor: RunThruTokens.shellTealDeep,
            itemCount: visibleBookmarks.length,
            itemBuilder: (context, index) {
              final bookmark = visibleBookmarks[index];
              return _ArticleRow(
                title: bookmark.title.isNotEmpty
                    ? bookmark.title
                    : bookmark.domain,
                source: 'instapaper',
                detail:
                    'Instapaper · ${_readingMinutes(bookmark.description)} min',
                unread: !bookmark.hasProgress,
                onTap: () => ref
                    .read(instapaperArticleImportProvider.notifier)
                    .importArticle(bookmark),
              );
            },
          ),
        );
      },
      loading: () => const SliverToBoxAdapter(
        child: _LibrarySection(
          title: 'Articles',
          countLabel: 'Loading',
          dotColor: RunThruTokens.shellTealDeep,
          itemCount: 0,
          empty: _SectionLoading(),
        ),
      ),
      error: (error, _) => SliverToBoxAdapter(
        child: _LibrarySection(
          title: 'Articles',
          countLabel: 'Issue',
          dotColor: RunThruTokens.shellTealDeep,
          itemCount: 0,
          empty: _SectionError(message: error.toString()),
        ),
      ),
    );
  }

  static int _readingMinutes(String text) {
    final words = text.trim().isEmpty ? 1200 : text.trim().split(' ').length;
    return (words / 238).ceil().clamp(1, 99);
  }
}

class _ArticleRow extends StatelessWidget {
  const _ArticleRow({
    required this.title,
    required this.source,
    required this.detail,
    required this.unread,
    required this.onTap,
  });

  final String title;
  final String source;
  final String detail;
  final bool unread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return RunThruShellRow(
      title: title,
      metadata: detail,
      icon: _iconForSource(source),
      semanticLabel: unread ? '$title, unread, $detail' : '$title, $detail',
      onTap: onTap,
      trailing: unread
          ? const RunThruStatusPill(label: 'New', tone: RunThruStatusTone.ready)
          : null,
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

class _SectionError extends StatelessWidget {
  const _SectionError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Text(
        'Failed to load: $message',
        style: RunThruTypography.caption.copyWith(
          color: RunThruTokens.shellError,
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
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
