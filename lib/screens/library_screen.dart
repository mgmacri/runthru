import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:speedy_boy/design/design.dart';
import 'package:speedy_boy/services/folder_scanner.dart';
import 'package:speedy_boy/services/models.dart';
import 'package:speedy_boy/services/preprocessing_queue.dart';
import 'package:speedy_boy/store/config.dart';
import 'package:speedy_boy/store/models.dart';
import 'package:speedy_boy/widgets/pdf_card_3d.dart';

/// Library screen — lists PDFs as 3D neumorphic cards.
class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pdfListAsync = ref.watch(pdfListProvider);
    final processed = ref.watch(preprocessingQueueProvider);
    final config = ref.watch(configProvider);
    final queue = ref.read(preprocessingQueueProvider.notifier);

    return Scaffold(
      backgroundColor: SpeedyBoyTokens.shellBase,
      body: SafeArea(
        child: Column(
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
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _ErrorBadge(count: queue.failedCount),
                        ),
                      IconButton(
                        onPressed: () => context.push('/discover'),
                        icon: const Icon(
                          Icons.explore,
                          color: SpeedyBoyTokens.shellTextSecondary,
                        ),
                        tooltip: 'Discover Books',
                      ),
                      IconButton(
                        onPressed: () => context.push('/analytics'),
                        icon: const Icon(
                          Icons.auto_graph,
                          color: SpeedyBoyTokens.shellTextSecondary,
                        ),
                      ),
                      IconButton(
                        onPressed: () => context.push('/settings'),
                        icon: const Icon(
                          Icons.settings,
                          color: SpeedyBoyTokens.shellTextSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // ── PDF List ──
            Expanded(
              child: pdfListAsync.when(
                data: (pdfList) => _buildList(
                  context,
                  ref,
                  pdfList,
                  processed,
                  config,
                ),
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
      ),
    );
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
          child: Text(
            'No PDF files found.\n\n'
            'Set a folder in Settings to get started.',
            style: SpeedyBoyTypography.body.copyWith(
              color: SpeedyBoyTokens.shellTextSecondary,
            ),
            textAlign: TextAlign.center,
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
        final bookmark =
            appConfig is AppConfig ? appConfig.bookmarks[entry.filePath] : null;
        final range = bookmark?.readingRange;
        double readingProgress = 0.0;
        String? rangeLabel;

        if (range != null) {
          final rangeStart = range.resolvedStartWordIndex;
          final rangeEnd = range.resolvedEndWordIndex;
          final rangeSize = rangeEnd - rangeStart;
          if (rangeSize > 0 && bookmark != null) {
            readingProgress =
                ((bookmark.wordIndex - rangeStart) / rangeSize).clamp(0.0, 1.0);
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
                  context.push(Uri(
                    path: '/read',
                    queryParameters: {'path': entry.filePath},
                  ).toString());
                }
              : null,
          onLongPress: displayEntry.status == PdfStatus.ready
              ? () {
                  HapticFeedback.mediumImpact();
                  context.push(Uri(
                    path: '/range-picker',
                    queryParameters: {'path': entry.filePath},
                  ).toString());
                }
              : null,
        );
      },
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
