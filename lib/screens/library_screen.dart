import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:speedy_boy/core/clipboard_service.dart';
import 'package:speedy_boy/core/hint_controller.dart';
import 'package:speedy_boy/design/design.dart';
import 'package:speedy_boy/services/folder_scanner.dart';
import 'package:speedy_boy/services/models.dart';
import 'package:speedy_boy/services/preprocessing_queue.dart';
import 'package:speedy_boy/store/config.dart';
import 'package:speedy_boy/store/models.dart';
import 'package:speedy_boy/widgets/hint_overlay.dart';
import 'package:speedy_boy/widgets/pdf_card_3d.dart';

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

    return Scaffold(
      backgroundColor: SpeedyBoyTokens.shellBase,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                // ── Header ──
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 16, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Speedy Boy',
                        style: SpeedyBoyTypography.display,
                      ),
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
                      style: SpeedyBoyTypography.caption.copyWith(
                        color: SpeedyBoyTokens.shellError,
                      ),
                    ),
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
                        style: SpeedyBoyTypography.body.copyWith(
                          color: SpeedyBoyTokens.shellTextSecondary,
                        ),
                      ),
                    ),
                    error: (error, _) => Center(
                      child: Text(
                        'Failed to scan folder:\n$error',
                        style: SpeedyBoyTypography.body.copyWith(
                          color: SpeedyBoyTokens.shellError,
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
        backgroundColor: SpeedyBoyTokens.shellBase,
        title: Text(
          doc.title,
          style: SpeedyBoyTypography.title.copyWith(
            color: SpeedyBoyTokens.shellTextPrimary,
          ),
        ),
        content: Text(
          preview,
          style: SpeedyBoyTypography.body.copyWith(
            color: SpeedyBoyTokens.shellTextSecondary,
          ),
          maxLines: 5,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: Text(
              'Cancel',
              style: SpeedyBoyTypography.body.copyWith(
                color: SpeedyBoyTokens.shellTextSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: Text(
              'Start Reading',
              style: SpeedyBoyTypography.body.copyWith(
                color: SpeedyBoyTokens.shellAccent,
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
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'No PDF files found.\n\n'
                'Set a folder in Settings to get started,\n'
                'or paste text from your clipboard.',
                style: SpeedyBoyTypography.body.copyWith(
                  color: SpeedyBoyTokens.shellTextSecondary,
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
                  decoration: SpeedyBoyDecorations.raisedDecoration(
                    SpeedyBoySurface.shell,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.content_paste,
                        color: SpeedyBoyTokens.shellAccent,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Paste from Clipboard',
                        style: SpeedyBoyTypography.body.copyWith(
                          color: SpeedyBoyTokens.shellAccent,
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
        decoration: SpeedyBoyDecorations.raisedDecoration(
          SpeedyBoySurface.shell,
          size: SpeedyBoyShadowSize.small,
          borderRadius: 12,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.content_paste,
              color: SpeedyBoyTokens.shellAccent,
              size: 16,
            ),
            const SizedBox(width: 4),
            Text(
              'Paste',
              style: SpeedyBoyTypography.caption.copyWith(
                color: SpeedyBoyTokens.shellAccent,
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
        color: SpeedyBoyTokens.shellError,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count failed',
        style: SpeedyBoyTypography.caption.copyWith(
          color: SpeedyBoyTokens.shellOnError,
        ),
      ),
    );
  }
}
