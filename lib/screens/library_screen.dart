import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:runthru/design/design.dart';
import 'package:runthru/features/content/providers/instapaper_auth_provider.dart';
import 'package:runthru/features/content/providers/instapaper_bookmarks_provider.dart';
import 'package:runthru/features/reading/providers/reading_progress_provider.dart';
import 'package:runthru/services/folder_scanner.dart';
import 'package:runthru/services/models.dart';
import 'package:runthru/services/preprocessing_queue.dart';
import 'package:runthru/store/config.dart';
import 'package:runthru/store/models.dart';

/// Content-type filter for the unified library.
enum _LibraryFilter { all, books, articles, docs }

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

  @override
  Widget build(BuildContext context) {
    final pdfListAsync = ref.watch(pdfListProvider);
    final processed = ref.watch(preprocessingQueueProvider);
    final config = ref.watch(configProvider);
    final queue = ref.read(preprocessingQueueProvider.notifier);
    // Watch the store so the shelf rebuilds when the async load resolves and
    // whenever reading progress is recorded; `shelf` reads the resolved value.
    ref.watch(readingProgressProvider);
    final rawShelf = ref.read(readingProgressProvider.notifier).shelf;
    // Filter local shelf items to only those whose source file is still active.
    // Non-local sources (Instapaper, Drive) are always included.
    final activePaths =
        pdfListAsync.valueOrNull?.map((e) => e.filePath).toSet();
    final shelf = activePaths == null
        ? rawShelf
        : rawShelf
            .where(
              (r) =>
                  r.source != 'local' || activePaths.contains(r.contentId),
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

    return Scaffold(
      backgroundColor: RunThruTokens.shellBase,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // ── Header ──
            SliverToBoxAdapter(
              child: _LibraryHeader(
                failedCount: queue.failedCount,
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
              const SliverToBoxAdapter(child: _SectionHeader(title: 'Books')),
              pdfListAsync.when(
                data: (list) {
                  final filteredList = _filterBooks(
                    list,
                    normalizedSearchQuery,
                  );
                  return filteredList.isEmpty
                      ? SliverToBoxAdapter(
                          child: _EmptyBooksState(
                            message: normalizedSearchQuery.isEmpty
                                ? null
                                : 'No books match this search.',
                          ),
                        )
                      : _BooksSliverGrid(
                          pdfList: filteredList,
                          processed: processed,
                          config: config,
                          onTap: _onBookTap,
                          onLongPress: _onBookLongPress,
                        );
                },
                loading: () =>
                    const SliverToBoxAdapter(child: _SectionLoading()),
                error: (e, _) => SliverToBoxAdapter(
                  child: _SectionError(message: e.toString()),
                ),
              ),
            ],

            // ── Articles section ──
            if (_filter == _LibraryFilter.all ||
                _filter == _LibraryFilter.articles) ...[
              const SliverToBoxAdapter(
                child: _SectionHeader(title: 'Articles'),
              ),
              _ArticlesSliverList(query: normalizedSearchQuery),
            ],

            // ── Docs section ──
            if (_filter == _LibraryFilter.all ||
                _filter == _LibraryFilter.docs) ...[
              const SliverToBoxAdapter(child: _SectionHeader(title: 'Docs')),
              const SliverToBoxAdapter(child: _EmptyDocsState()),
            ],

            const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
          ],
        ),
      ),
    );
  }

  void _onShelfItemTap(ProgressRecord item) {
    // Navigate to the correct reader for the content type.
    if (item.contentId.startsWith('instapaper://')) {
      _resumeInstapaperItem(item);
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
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Expanded(
                child: Text('Library', style: RunThruTypography.title),
              ),
              if (failedCount > 0) _ErrorBadge(count: failedCount),
              const SizedBox(width: 4),
              _HeaderIconButton(
                icon: isSearchOpen ? Icons.close_rounded : Icons.search_rounded,
                tooltip: isSearchOpen ? 'Close search' : 'Search',
                onPressed: onSearchToggle,
              ),
              _HeaderIconButton(
                icon: Icons.cloud_outlined,
                tooltip: 'Sources',
                onPressed: () => context.go('/sources'),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              const Icon(
                Icons.sync_rounded,
                size: 13,
                color: RunThruTokens.shellTextSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                'Synced just now · $sourceCount ${sourceCount == 1 ? 'source' : 'sources'}',
                style: RunThruTypography.caption.copyWith(
                  color: RunThruTokens.shellTextSecondary,
                ),
              ),
            ],
          ),
          if (isSearchOpen) ...[
            const SizedBox(height: 12),
            _LibrarySearchField(
              initialValue: searchQuery,
              onChanged: onSearchChanged,
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
        decoration: RunThruDecorations.insetDecoration(
          RunThruSurface.shell,
          size: RunThruShadowSize.small,
          borderRadius: 12,
        ),
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

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: tooltip,
      button: true,
      child: SizedBox(
        width: 44,
        height: 44,
        child: IconButton(
          icon: Icon(icon, size: 22),
          color: RunThruTokens.shellTextSecondary,
          onPressed: onPressed,
          tooltip: tooltip,
        ),
      ),
    );
  }
}
// ─────────────────────────────────────────────────────────────────────────────
// Continue Reading shelf
// ─────────────────────────────────────────────────────────────────────────────

class _ContinueReadingShelf extends StatelessWidget {
  const _ContinueReadingShelf({required this.items, required this.onItemTap});

  final List<ProgressRecord> items;
  final void Function(ProgressRecord) onItemTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(title: 'Continue reading', topPadding: 0),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text(
                'Nothing in progress yet',
                style: RunThruTypography.caption.copyWith(
                  color: RunThruTokens.shellTextSecondary,
                ),
              ),
            )
          else
            SizedBox(
              height: 150,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                scrollDirection: Axis.horizontal,
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) => _ShelfCard(
                  item: items[index],
                  onTap: () => onItemTap(items[index]),
                ),
              ),
            ),
        ],
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
    final minutesLeft = widget.item.minutesLeft;
    final timeLabel = minutesLeft <= 1
        ? '<1 min left'
        : '$minutesLeft min left';
    final reduced = isReducedMotion(context);
    final decoration = _pressed
        ? RunThruDecorations.insetDecoration(
            RunThruSurface.shell,
            size: RunThruShadowSize.small,
            borderRadius: 12,
          )
        : RunThruDecorations.raisedDecoration(
            RunThruSurface.shell,
            size: RunThruShadowSize.small,
            borderRadius: 12,
          );

    return Semantics(
      label:
          '${widget.item.title}, ${widget.item.source}, $percent percent read',
      button: true,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: reduced ? Duration.zero : const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          width: 126,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 76,
                decoration: decoration,
                child: Stack(
                  children: [
                    Center(
                      child: Icon(
                        _iconForSource(widget.item.source),
                        size: 28,
                        color: _sourceColor(widget.item.source),
                      ),
                    ),
                    Positioned(
                      top: 7,
                      right: 7,
                      child: _SourceBadge(source: widget.item.source),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 7),
              // Flexible so a long title (or larger text-scale) ellipsises
              // instead of overflowing the fixed-height shelf row.
              Flexible(
                child: Text(
                  widget.item.title,
                  style: RunThruTypography.caption.copyWith(
                    color: RunThruTokens.shellTextPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 5),
              _ProgressBar(
                value: widget.item.percent,
                color: _sourceColor(widget.item.source),
                height: 4,
              ),
              const SizedBox(height: 3),
              Text(
                percent > 0 ? '$percent%' : timeLabel,
                style: RunThruTypography.caption.copyWith(
                  color: RunThruTokens.shellTextSecondary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({
    required this.value,
    required this.color,
    this.height = 4,
  });

  final double value;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${(value.clamp(0.0, 1.0) * 100).round()} percent read',
      child: Container(
        height: height,
        decoration: RunThruDecorations.insetDecoration(
          RunThruSurface.shell,
          size: RunThruShadowSize.small,
          borderRadius: height / 2,
        ),
        clipBehavior: Clip.antiAlias,
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: value.clamp(0.0, 1.0),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(height / 2),
              ),
              child: const SizedBox.expand(),
            ),
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
    final reduced = isReducedMotion(context);
    return SizedBox(
      height: 54,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
        scrollDirection: Axis.horizontal,
        children: _LibraryFilter.values.map((filter) {
          final isSelected = filter == selected;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Semantics(
              label: '${_labels[filter]} filter',
              selected: isSelected,
              button: true,
              child: GestureDetector(
                onTap: () => onChanged(filter),
                child: AnimatedContainer(
                  duration: reduced
                      ? Duration.zero
                      : const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 15,
                    vertical: 7,
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 38,
                  ),
                  decoration: isSelected
                      ? RunThruDecorations.insetDecoration(
                          RunThruSurface.shell,
                          size: RunThruShadowSize.small,
                          borderRadius: 999,
                        )
                      : RunThruDecorations.raisedDecoration(
                          RunThruSurface.shell,
                          size: RunThruShadowSize.small,
                          borderRadius: 999,
                        ),
                  child: Text(
                    _labels[filter]!,
                    style: RunThruTypography.caption.copyWith(
                      color: isSelected
                          ? RunThruTokens.shellTextPrimary
                          : RunThruTokens.shellTextSecondary,
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
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
      child: Text(
        title,
        style: RunThruTypography.caption.copyWith(
          color: RunThruTokens.shellTextSecondary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Books grid
// ─────────────────────────────────────────────────────────────────────────────

class _BooksSliverGrid extends StatelessWidget {
  const _BooksSliverGrid({
    required this.pdfList,
    required this.processed,
    required this.config,
    required this.onTap,
    required this.onLongPress,
  });

  final List<PdfEntry> pdfList;
  final Map<String, PdfEntry> processed;
  final AsyncValue<dynamic> config;
  final void Function(PdfEntry) onTap;
  final void Function(PdfEntry) onLongPress;

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      sliver: SliverGrid.builder(
        itemCount: pdfList.length,
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 220,
          mainAxisSpacing: 14,
          crossAxisSpacing: 14,
          childAspectRatio: 0.76,
        ),
        itemBuilder: (context, index) {
          final entry = pdfList[index];
          final processedEntry = processed[entry.filePath];
          final displayEntry = processedEntry ?? entry;

          final appConfig = config.valueOrNull;
          final bookmark = appConfig is AppConfig
              ? appConfig.bookmarks[entry.filePath]
              : null;
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
          } else if (bookmark != null && displayEntry.document != null) {
            final totalWords = displayEntry.document!.totalWords;
            if (totalWords > 0) {
              readingProgress = (bookmark.wordIndex / totalWords).clamp(
                0.0,
                1.0,
              );
            }
          }

          return _BookTile(
            entry: displayEntry,
            progress: readingProgress,
            rangeLabel: rangeLabel,
            onTap: displayEntry.status == PdfStatus.ready
                ? () => onTap(entry)
                : null,
            // Long-press opens the reading-range picker for any ready book.
            // RangePickerScreen itself shows a "PDF only" notice for
            // non-PDF formats, so the tile must still navigate rather than
            // swallow the gesture.
            onLongPress: displayEntry.status == PdfStatus.ready
                ? () => onLongPress(entry)
                : null,
          );
        },
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
    this.rangeLabel,
  });

  final PdfEntry entry;
  final double progress;
  final String? rangeLabel;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  State<_BookTile> createState() => _BookTileState();
}

class _BookTileState extends State<_BookTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final reduced = isReducedMotion(context);
    final statusColor = _statusColor(widget.entry.status);
    final decoration = _pressed
        ? RunThruDecorations.insetDecoration(
            RunThruSurface.shell,
            size: RunThruShadowSize.small,
            borderRadius: 12,
          )
        : RunThruDecorations.raisedDecoration(
            RunThruSurface.shell,
            size: RunThruShadowSize.small,
            borderRadius: 12,
          );

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
        child: AnimatedContainer(
          duration: reduced ? Duration.zero : const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  decoration: decoration,
                  child: Stack(
                    children: [
                      Center(
                        child: Icon(
                          Icons.menu_book_rounded,
                          size: 34,
                          color: statusColor,
                        ),
                      ),
                      const Positioned(
                        top: 8,
                        right: 8,
                        child: _SourceBadge(source: 'local'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.entry.fileName,
                style: RunThruTypography.caption.copyWith(
                  color: RunThruTokens.shellTextPrimary,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                widget.rangeLabel ?? _statusLabel(widget.entry),
                style: RunThruTypography.caption.copyWith(
                  color: RunThruTokens.shellTextSecondary,
                  fontSize: 11,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (widget.progress > 0) ...[
                const SizedBox(height: 6),
                _ProgressBar(
                  value: widget.progress,
                  color: RunThruTokens.shellAccent,
                  height: 4,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static Color _statusColor(PdfStatus status) {
    return switch (status) {
      PdfStatus.ready => RunThruTokens.shellReady,
      PdfStatus.processing ||
      PdfStatus.preview => RunThruTokens.shellProcessing,
      PdfStatus.error ||
      PdfStatus.unsupported ||
      PdfStatus.permanentlyFailed => RunThruTokens.shellError,
      PdfStatus.pending || PdfStatus.queued => RunThruTokens.shellTextSecondary,
    };
  }

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
        return const SliverToBoxAdapter(child: _SectionLoading());
      case InstapaperAuthUnauthenticated():
      case InstapaperAuthLegacyFallbackRequired():
        return const SliverToBoxAdapter(child: _EmptyArticlesState());
      case InstapaperAuthError(:final message):
        return SliverToBoxAdapter(
          child: _ArticlesAuthErrorTile(message: message),
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
            child: _EmptyArticlesState(
              message: query.isEmpty ? null : 'No articles match this search.',
            ),
          );
        }
        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          sliver: SliverList.separated(
            itemCount: visibleBookmarks.length,
            separatorBuilder: (_, __) => const SizedBox(height: 1),
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
      loading: () => const SliverToBoxAdapter(child: _SectionLoading()),
      error: (error, _) =>
          SliverToBoxAdapter(child: _SectionError(message: error.toString())),
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
    return Semantics(
      label: unread ? '$title, unread, $detail' : '$title, $detail',
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: RunThruTokens.shellDarkShadow.withValues(alpha: 0.7),
                width: 0.5,
              ),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: RunThruDecorations.raisedDecoration(
                  RunThruSurface.shell,
                  size: RunThruShadowSize.small,
                  borderRadius: 10,
                ),
                child: Icon(
                  _iconForSource(source),
                  size: 19,
                  color: _sourceColor(source),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: RunThruTypography.caption.copyWith(
                        color: RunThruTokens.shellTextPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      style: RunThruTypography.caption.copyWith(
                        color: RunThruTokens.shellTextSecondary,
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (unread) ...[
                const SizedBox(width: 12),
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: RunThruTokens.shellAccent,
                  ),
                ),
              ],
            ],
          ),
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

IconData _iconForSource(String source) => switch (source) {
  'instapaper' => Icons.bookmark_rounded,
  'drive' => Icons.cloud_outlined,
  'substack' => Icons.mail_outline_rounded,
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
