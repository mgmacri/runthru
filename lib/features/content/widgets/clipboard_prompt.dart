import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runthru/core/clipboard_document.dart';
import 'package:runthru/design/design.dart';
import 'package:runthru/features/content/providers/clipboard_detect_provider.dart';

/// Displays a non-intrusive prompt when clipboard text is detected.
///
/// Shows a preview of the clipboard content with "Import to Library"
/// and "Dismiss" buttons. Does NOT auto-import — explicit user tap
/// required (Rule 28 / privacy-by-default).
///
/// Uses design system tokens for all colors and text styles.
/// Touch targets are ≥48dp per accessibility requirements.
class ClipboardPrompt extends ConsumerWidget {
  /// Creates a [ClipboardPrompt] widget.
  const ClipboardPrompt({super.key, required this.onImport});

  /// Called when the user taps "Import to Library" with the parsed document.
  final void Function(ClipboardDocument document) onImport;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clipboardState = ref.watch(clipboardDetectProvider);

    if (!clipboardState.shouldShowPrompt) {
      return const SizedBox.shrink();
    }

    return Semantics(
      label: 'Clipboard content detected: ${clipboardState.preview}',
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.all(16),
        decoration: RunThruDecorations.raisedDecoration(
          RunThruSurface.shell,
          size: RunThruShadowSize.small,
          borderRadius: 12,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.content_paste_rounded,
                  color: RunThruTokens.shellAccent,
                  size: 20,
                  semanticLabel: 'Clipboard',
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Clipboard text detected',
                    style: RunThruTypography.body.copyWith(
                      fontWeight: FontWeight.w500,
                      color: RunThruTokens.shellTextPrimary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '"${clipboardState.preview}"  \u2022  ${clipboardState.wordCount} words',
              style: RunThruTypography.caption.copyWith(
                color: RunThruTokens.shellTextSecondary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Dismiss button — ≥48dp touch target.
                Semantics(
                  button: true,
                  label: 'Dismiss clipboard prompt',
                  child: GestureDetector(
                    onTap: () {
                      ref.read(clipboardDetectProvider.notifier).dismiss();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      constraints: const BoxConstraints(minHeight: 48),
                      child: Text(
                        'Dismiss',
                        style: RunThruTypography.body.copyWith(
                          color: RunThruTokens.shellTextSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Import button — ≥48dp touch target.
                Semantics(
                  button: true,
                  label: 'Import clipboard text to library',
                  child: GestureDetector(
                    onTap: () => _handleImport(ref),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      constraints: const BoxConstraints(minHeight: 48),
                      decoration: RunThruDecorations.raisedDecoration(
                        RunThruSurface.shell,
                        size: RunThruShadowSize.small,
                        borderRadius: 8,
                      ),
                      child: Text(
                        'Import to Library',
                        style: RunThruTypography.body.copyWith(
                          color: RunThruTokens.shellAccent,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleImport(WidgetRef ref) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.trim().isEmpty) return;

    final doc = ClipboardDocument.fromClipboardText(text);
    ref.read(clipboardDetectProvider.notifier).clear();
    onImport(doc);
  }
}
