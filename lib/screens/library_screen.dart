import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:runthru/core/clipboard_document.dart';
import 'package:runthru/core/clipboard_service.dart';
import 'package:runthru/core/hint_controller.dart';
import 'package:runthru/design/design.dart';
import 'package:runthru/features/content/providers/file_picker_provider.dart';
import 'package:runthru/features/content/providers/instapaper_bookmarks_provider.dart';
import 'package:runthru/features/content/widgets/clipboard_prompt.dart';
import 'package:runthru/features/content/widgets/instapaper_bookmark_list.dart';
import 'package:runthru/services/folder_scanner.dart';
import 'package:runthru/services/models.dart';
import 'package:runthru/services/preprocessing_queue.dart';
import 'package:runthru/store/config.dart';
import 'package:runthru/store/models.dart';
import 'package:runthru/widgets/hint_overlay.dart';
import 'package:runthru/widgets/pdf_card_3d.dart';

/// Library screen — lists PDFs as 3D neumorphic cards.
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  final ClipboardService _clipboardService = ClipboardService();
  String? _clipboardError;
  bool _showClipboardHint = false;

  @override
  Widget build(BuildContext context) {
    final pdfListAsync = ref.watch(pdfListProvider);
    final processed = ref.watch(preprocessingQueueProvider);
    final config = ref.watch(configProvider);
    final queue = ref.read(preprocessingQueueProvider.notifier);
    final filePickerState = ref.watch(filePickerNotifierProvider);

    // Listen for Instapaper article import state changes
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
      // ── File Picker FAB ──
      floatingActionButton: Semantics(
        button: true,
        label: 'Import file',
        child: SizedBox(
          width: 56,
          height: 56,
          child: FloatingActionButton(
            onPressed:
                filePickerState is FilePickerPicking ||
                    filePickerState is FilePickerExtracting
                ? null
                : () => ref
                      .read(filePickerNotifierProvider.notifier)
                      .pickAndExtract(),
            backgroundColor: RunThruTokens.shellAccent,
            child: filePickerState is FilePickerExtracting
                ? SizedBox(
                    width: 24,
                    height: 24,
                    child: Text(
                      '…',
                      style: RunThruTypography.body.copyWith(
                        color: RunThruTokens.shellOnError,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  )
                : const Icon(
                    Icons.add_rounded,
                    color: RunThruTokens.shellOnError,
                    semanticLabel: 'Import file',
                  ),
          ),
        ),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                // ── File Picker Progress Banner ──
                if (filePickerState is FilePickerExtracting)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 8,
                    ),
                    color: RunThruTokens.shellProcessing.withValues(
                      alpha: 0.15,
                    ),
                    child: Text(
                      'Extracting ${filePickerState.fileName}\u2026',
                      style: RunThruTypography.caption.copyWith(
                        color: RunThruTokens.shellTextPrimary,
                      ),
                    ),
                  ),
                if (filePickerState is FilePickerError)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 8,
                    ),
                    color: RunThruTokens.shellError.withValues(alpha: 0.15),
                    child: Text(
                      filePickerState.message,
                      style: RunThruTypography.caption.copyWith(
                        color: RunThruTokens.shellError,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                // ── Header ──
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 16, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('RunThru', style: RunThruTypography.display),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (queue.failedCount > 0)
                            _ErrorBadge(count: queue.failedCount),
                          const SizedBox(width: 8),
                          _PasteButton(onPressed: () => _handlePaste(context)),
                        ],
                      ),
                    ],
                  ),
                ),
                // ── Clipboard error message ──
                if (_clipboardError != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 4,
                    ),
                    child: Text(
                      _clipboardError!,
                      style: RunThruTypography.caption.copyWith(
                        color: RunThruTokens.shellError,
                      ),
                    ),
                  ),

                // ── Clipboard Auto-Detect Prompt ──
                ClipboardPrompt(
                  onImport: (ClipboardDocument doc) {
                    context.push('/read-clipboard', extra: doc);
                  },
                ),

                // ── Instapaper Section ──
                const SizedBox(height: 16),
                InstapaperSection(
                  onBookmarkTap: (bookmark) {
                    ref
                        .read(instapaperArticleImportProvider.notifier)
                        .importArticle(bookmark);
                  },
                ),

                // ── PDF List ──
                Expanded(
                  child: pdfListAsync.when(
                    data: (pdfList) {
                      // P27 — show clipboard hint on empty library (first time)
                      _maybeShowClipboardHint(pdfList);
                      return _buildList(
                        context,
                        ref,
                        pdfList,
                        processed,
                        config,
                      );
                    },
                    loading: () => Center(
                      child: Text(
                        'Loading…',
                        style: RunThruTypography.body.copyWith(
                          color: RunThruTokens.shellTextSecondary,
                        ),
                      ),
                    ),
                    error: (error, _) => Center(
                      child: Text(
                        'Failed to scan folder:\n$error',
                        style: RunThruTypography.body.copyWith(
                          color: RunThruTokens.shellError,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            // ── Clipboard Hint Overlay (Rule 27) ──
            if (_showClipboardHint)
              HintOverlay(
                text: 'Paste text from clipboard to read',
                position: Alignment.topRight,
                slideFrom: AxisDirection.right,
                onDismiss: _dismissClipboardHint,
              ),
          ],
        ),
      ),
    );
  }

  void _maybeShowClipboardHint(List<PdfEntry> pdfList) {
    if (!_showClipboardHint &&
        pdfList.isEmpty &&
        !ref.read(configProvider.notifier).hasHintBeenShown(HintId.clipboard)) {
      // Schedule hint after build completes.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _showClipboardHint = true);
      });
    }
  }

  void _dismissClipboardHint() {
    ref.read(configProvider.notifier).markHintShown(HintId.clipboard);
    setState(() => _showClipboardHint = false);
  }

  Future<void> _handlePaste(BuildContext ctx) async {
    setState(() => _clipboardError = null);
    final doc = await _clipboardService.readFromClipboard();
    if (!ctx.mounted) return;

    if (doc == null) {
      setState(
        () => _clipboardError = 'Nothing to read — copy some text first',
      );
      return;
    }

    // Show preview dialog before navigating.
    final preview = doc.fullText.length > 100
        ? '${doc.fullText.substring(0, 100)}\u2026'
        : doc.fullText;

    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: RunThruTokens.shellBase,
        title: Text(
          doc.title,
          style: RunThruTypography.title.copyWith(
            color: RunThruTokens.shellTextPrimary,
          ),
        ),
        content: Text(
          preview,
          style: RunThruTypography.body.copyWith(
            color: RunThruTokens.shellTextSecondary,
          ),
          maxLines: 5,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: Text(
              'Cancel',
              style: RunThruTypography.body.copyWith(
                color: RunThruTokens.shellTextSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: Text(
              'Start Reading',
              style: RunThruTypography.body.copyWith(
                color: RunThruTokens.shellAccent,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && ctx.mounted) {
      ctx.push('/read-clipboard', extra: doc);
    }
  }

  Widget _buildList(
    BuildContext context,
    WidgetRef ref,
    List<PdfEntry> pdfList,
    Map<String, PdfEntry> processed,
    AsyncValue<dynamic> config,
  ) {
    if (pdfList.isEmpty) {
      return SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'No PDF files found.\n\n'
                'Set a folder in Settings to get started,\n'
                'or paste text from your clipboard.',
                style: RunThruTypography.body.copyWith(
                  color: RunThruTokens.shellTextSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              // Prominent paste CTA in empty state
              GestureDetector(
                onTap: () => _handlePaste(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 14,
                  ),
                  decoration: RunThruDecorations.raisedDecoration(
                    RunThruSurface.shell,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.content_paste,
                        color: RunThruTokens.shellAccent,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Paste from Clipboard',
                        style: RunThruTypography.body.copyWith(
                          color: RunThruTokens.shellAccent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: pdfList.length,
      itemBuilder: (context, index) {
        final entry = pdfList[index];
        final processedEntry = processed[entry.filePath];
        final displayEntry = processedEntry ?? entry;

        // Compute range-aware progress and label.
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
          rangeLabel = 'Pages ${range.startPage + 1}\u2013${range.endPage + 1}';
        } else if (bookmark != null && displayEntry.document != null) {
          final totalWords = displayEntry.document!.totalWords;
          if (totalWords > 0) {
            readingProgress = (bookmark.wordIndex / totalWords).clamp(0.0, 1.0);
          }
        }

        return PdfCard3D(
          entry: displayEntry,
          readingProgress: readingProgress,
          rangeLabel: rangeLabel,
          onTap: displayEntry.status == PdfStatus.ready
              ? () {
                  context.push(
                    Uri(
                      path: '/read',
                      queryParameters: {'path': entry.filePath},
                    ).toString(),
                  );
                }
              : null,
          onLongPress: displayEntry.status == PdfStatus.ready
              ? () {
                  HapticFeedback.mediumImpact();
                  context.push(
                    Uri(
                      path: '/range-picker',
                      queryParameters: {'path': entry.filePath},
                    ).toString(),
                  );
                }
              : null,
        );
      },
    );
  }
}

/// Compact paste button for the header row.
class _PasteButton extends StatelessWidget {
  const _PasteButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: RunThruDecorations.raisedDecoration(
          RunThruSurface.shell,
          size: RunThruShadowSize.small,
          borderRadius: 12,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.content_paste,
              color: RunThruTokens.shellAccent,
              size: 16,
            ),
            const SizedBox(width: 4),
            Text(
              'Paste',
              style: RunThruTypography.caption.copyWith(
                color: RunThruTokens.shellAccent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
