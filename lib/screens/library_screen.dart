import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:speedy_boy/design/design.dart';
import 'package:speedy_boy/services/folder_scanner.dart';
import 'package:speedy_boy/services/models.dart';
import 'package:speedy_boy/services/preprocessing_queue.dart';
import 'package:speedy_boy/store/config.dart';
import 'package:speedy_boy/widgets/pdf_card_3d.dart';

/// Library screen — lists PDFs as 3D neumorphic cards.
class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pdfList = ref.watch(pdfListProvider);
    final processed = ref.watch(preprocessingQueueProvider);
    final config = ref.watch(configProvider);

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
                  IconButton(
                    onPressed: () => context.push('/settings'),
                    icon: const Icon(
                      Icons.settings,
                      color: SpeedyBoyTokens.shellTextSecondary,
                    ),
                  ),
                ],
              ),
            ),

            // ── PDF List ──
            Expanded(
              child: _buildList(
                context,
                pdfList,
                processed,
                config,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(
    BuildContext context,
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

        return PdfCard3D(
          entry: displayEntry,
          onTap: displayEntry.status == PdfStatus.ready
              ? () {
                  context.push(Uri(
                    path: '/read',
                    queryParameters: {'path': entry.filePath},
                  ).toString());
                }
              : null,
        );
      },
    );
  }
}
