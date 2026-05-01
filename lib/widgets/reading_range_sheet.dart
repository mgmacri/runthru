import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:runthru/design/design.dart';
import 'package:runthru/services/models.dart';

/// Modal bottom sheet for setting a reading range (start/end page + word).
///
/// Usage:
/// ```dart
/// showModalBottomSheet(
///   context: context,
///   builder: (_) => ReadingRangeSheet(
///     pageBoundaries: ...,
///     currentRange: ...,
///     onRangeSet: (range) { ... },
///     onRangeCleared: () { ... },
///   ),
/// );
/// ```
class ReadingRangeSheet extends StatefulWidget {
  const ReadingRangeSheet({
    super.key,
    required this.pageBoundaries,
    required this.totalPages,
    this.currentRange,
    required this.onRangeSet,
    required this.onRangeCleared,
  });

  final List<PageBoundary> pageBoundaries;
  final int totalPages;
  final ReadingRange? currentRange;
  final ValueChanged<ReadingRange> onRangeSet;
  final VoidCallback onRangeCleared;

  @override
  State<ReadingRangeSheet> createState() => _ReadingRangeSheetState();
}

class _ReadingRangeSheetState extends State<ReadingRangeSheet> {
  late final TextEditingController _startPageCtrl;
  late final TextEditingController _startWordCtrl;
  late final TextEditingController _endPageCtrl;
  late final TextEditingController _endWordCtrl;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    final r = widget.currentRange;
    _startPageCtrl =
        TextEditingController(text: r != null ? '${r.startPage + 1}' : '');
    _startWordCtrl = TextEditingController(
        text: r != null ? '${r.startWordIndexOnPage}' : '');
    _endPageCtrl =
        TextEditingController(text: r != null ? '${r.endPage + 1}' : '');
    _endWordCtrl =
        TextEditingController(text: r != null ? '${r.endWordIndexOnPage}' : '');
  }

  @override
  void dispose() {
    _startPageCtrl.dispose();
    _startWordCtrl.dispose();
    _endPageCtrl.dispose();
    _endWordCtrl.dispose();
    super.dispose();
  }

  void _validate() {
    final startPage = int.tryParse(_startPageCtrl.text);
    final endPage = int.tryParse(_endPageCtrl.text);

    if (startPage == null || endPage == null) {
      setState(() => _errorText = 'Enter valid page numbers');
      return;
    }
    if (startPage < 1 || endPage < 1) {
      setState(() => _errorText = 'Page numbers must be ≥ 1');
      return;
    }
    if (startPage > endPage) {
      setState(() => _errorText = 'Start page must be ≤ end page');
      return;
    }
    if (startPage > widget.totalPages || endPage > widget.totalPages) {
      setState(() => _errorText = 'Max page is ${widget.totalPages}');
      return;
    }

    final startWord = int.tryParse(_startWordCtrl.text) ?? 0;
    final endWord = int.tryParse(_endWordCtrl.text) ?? 0;

    if (startPage == endPage && startWord > endWord) {
      setState(() => _errorText = 'Start word must be ≤ end word on same page');
      return;
    }

    setState(() => _errorText = null);

    // Convert 1-based display to 0-based internal
    final range = ReadingRange(
      startPage: startPage - 1,
      startWordIndexOnPage: startWord,
      endPage: endPage - 1,
      endWordIndexOnPage: endWord,
    );

    // Resolve global indices
    final resolved = resolveRange(range, widget.pageBoundaries);
    final resolvedRange = range.copyWith(
      resolvedStartWordIndex: resolved.globalStart,
      resolvedEndWordIndex: resolved.globalEnd,
    );

    widget.onRangeSet(resolvedRange);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.paddingOf(context).bottom + 24,
      ),
      decoration: RunThruDecorations.raisedDecoration(
        RunThruSurface.shell,
        borderRadius: 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Reading Range', style: RunThruTypography.title),
          const SizedBox(height: 16),

          // ── START section ──
          const Text('START', style: RunThruTypography.caption),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _InsetTextField(
                  controller: _startPageCtrl,
                  label: 'Page',
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _InsetTextField(
                  controller: _startWordCtrl,
                  label: 'Word #',
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── END section ──
          const Text('END', style: RunThruTypography.caption),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _InsetTextField(
                  controller: _endPageCtrl,
                  label: 'Page',
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _InsetTextField(
                  controller: _endWordCtrl,
                  label: 'Word #',
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
              ),
            ],
          ),

          // ── Error text ──
          if (_errorText != null) ...[
            const SizedBox(height: 8),
            Text(
              _errorText!,
              style: RunThruTypography.caption.copyWith(
                color: RunThruTokens.shellError,
              ),
            ),
          ],

          const SizedBox(height: 24),

          // ── Actions ──
          Row(
            children: [
              TextButton(
                onPressed: () {
                  widget.onRangeCleared();
                  Navigator.of(context).pop();
                },
                child: Text(
                  'Clear Range',
                  style: RunThruTypography.body.copyWith(
                    color: RunThruTokens.shellTextSecondary,
                  ),
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  'Cancel',
                  style: RunThruTypography.body.copyWith(
                    color: RunThruTokens.shellTextSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _validate,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: RunThruDecorations.raisedDecoration(
                    RunThruSurface.shell,
                    size: RunThruShadowSize.small,
                    borderRadius: 12,
                  ),
                  child: Text(
                    'Set Range',
                    style: RunThruTypography.body.copyWith(
                      color: RunThruTokens.shellAccent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Neumorphic inset text field matching shell surface.
class _InsetTextField extends StatelessWidget {
  const _InsetTextField({
    required this.controller,
    required this.label,
    this.keyboardType,
    this.inputFormatters,
  });

  final TextEditingController controller;
  final String label;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: RunThruDecorations.insetDecoration(
        RunThruSurface.shell,
        size: RunThruShadowSize.small,
        borderRadius: 10,
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        style: RunThruTypography.body,
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: label,
          hintStyle: RunThruTypography.caption,
          isDense: true,
          contentPadding: EdgeInsets.zero,
        ),
      ),
    );
  }
}
