import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:speedy_boy/core/reading_range_resolver.dart';
import 'package:speedy_boy/design/design.dart';
import 'package:speedy_boy/services/models.dart';
import 'package:speedy_boy/services/preprocessing_queue.dart';
import 'package:speedy_boy/store/config.dart';
import 'package:speedy_boy/store/models.dart';
import 'package:speedy_boy/widgets/range_confirmation_modal.dart';

/// Selection phase for the two-phase range picking flow.
enum _SelectionPhase { start, end }

/// Captured word selection data.
class _WordSelection {
  const _WordSelection({
    required this.page,
    required this.wordIndexOnPage,
    required this.wordText,
  });

  /// 0-indexed page number.
  final int page;

  /// 0-indexed word position within the page.
  final int wordIndexOnPage;

  /// The selected word text.
  final String wordText;
}

/// Full-screen PDF viewer for selecting a reading range (start word → end word).
class RangePickerScreen extends ConsumerStatefulWidget {
  const RangePickerScreen({super.key, required this.filePath});

  final String filePath;

  @override
  ConsumerState<RangePickerScreen> createState() => _RangePickerScreenState();
}

class _RangePickerScreenState extends ConsumerState<RangePickerScreen>
    with SingleTickerProviderStateMixin {
  final PdfViewerController _pdfController = PdfViewerController();
  late final AnimationController _buttonAnimController;

  // ── ValueNotifiers for fast-changing state (no setState rebuilds) ──
  final ValueNotifier<_SelectionPhase> _phaseNotifier = ValueNotifier(
    _SelectionPhase.start,
  );
  final ValueNotifier<_WordSelection?> _startNotifier = ValueNotifier(null);
  final ValueNotifier<_WordSelection?> _endNotifier = ValueNotifier(null);
  final ValueNotifier<String?> _errorNotifier = ValueNotifier(null);
  final ValueNotifier<int> _currentPageNotifier = ValueNotifier(1);
  final ValueNotifier<int> _totalPagesNotifier = ValueNotifier(0);

  /// Debounce timer for text selection callbacks.
  Timer? _debounceTimer;

  /// Set once during init — does not change after.
  bool _hasExistingRange = false;

  /// Page boundaries from the extracted document.
  List<PageBoundary> _pageBoundaries = [];

  /// All words from the extracted document.
  List<String> _allWords = [];

  /// O(1) page → boundary lookup (built once).
  Map<int, PageBoundary> _boundaryByPage = {};

  /// O(1) page → end word index lookup (built once).
  Map<int, int> _pageEndWordIndex = {};

  @override
  void initState() {
    super.initState();
    _buttonAnimController = SpeedyBoyAnimations.createController(
      vsync: this,
      duration: SpeedyBoyAnimations.dialEmergeDuration,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadExistingRange();
    });
  }

  @override
  void dispose() {
    _buttonAnimController.dispose();
    _debounceTimer?.cancel();
    _phaseNotifier.dispose();
    _startNotifier.dispose();
    _endNotifier.dispose();
    _errorNotifier.dispose();
    _currentPageNotifier.dispose();
    _totalPagesNotifier.dispose();
    super.dispose();
  }

  void _loadExistingRange() {
    final config = ref.read(configProvider).valueOrNull ?? const AppConfig();
    final bookmark = config.bookmarks[widget.filePath];
    final range = bookmark?.readingRange;

    // Load page boundaries from extracted document.
    final processed = ref.read(preprocessingQueueProvider);
    final entry = processed[widget.filePath];
    if (entry?.document != null) {
      _pageBoundaries = entry!.document!.pageBoundaries;
      _allWords = entry.document!.allWords;
      _buildBoundaryMaps();
    }

    if (range != null) {
      _hasExistingRange = true;
      _startNotifier.value = _WordSelection(
        page: range.startPage,
        wordIndexOnPage: range.startWordIndexOnPage,
        wordText: range.startWordAnchor ?? '',
      );
      _endNotifier.value = _WordSelection(
        page: range.endPage,
        wordIndexOnPage: range.endWordIndexOnPage,
        wordText: range.endWordAnchor ?? '',
      );
      _phaseNotifier.value = _SelectionPhase.end;

      // Trigger one rebuild for header "Clear Range" button visibility.
      setState(() {});

      // Pre-scroll to start page.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final totalPages = _totalPagesNotifier.value;
        if (range.startPage > 0 && range.startPage <= totalPages) {
          _pdfController.goToPage(pageNumber: range.startPage);
        }
      });
    }
  }

  /// Build O(1) lookup maps from the page boundaries list.
  void _buildBoundaryMaps() {
    _boundaryByPage = {for (final b in _pageBoundaries) b.pageNumber: b};

    final sorted = _pageBoundaries.toList()
      ..sort((a, b) => a.pageNumber.compareTo(b.pageNumber));
    _pageEndWordIndex = {};
    for (var i = 0; i < sorted.length; i++) {
      final nextStart = (i + 1 < sorted.length)
          ? sorted[i + 1].startWordIndex
          : _allWords.length;
      _pageEndWordIndex[sorted[i].pageNumber] = nextStart;
    }
  }

  void _onTextSelectionChanged(PdfTextSelection selection) {
    if (!selection.hasSelectedText) return;

    // Debounce: only process after 150ms of no new selection events.
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 150), () async {
      final text = await selection.getSelectedText();
      if (text.isNotEmpty) {
        _processSelection(text);
      }
    });
  }

  void _processSelection(String selectedText) {
    final trimmed = selectedText.trim();
    final words = trimmed.split(RegExp(r'\s+'));
    if (words.isEmpty) return;

    final word = words.first;
    final page = _currentPageNotifier.value - 1; // 0-indexed

    final wordOnPage = _findWordIndexOnPage(page, word);

    final selection = _WordSelection(
      page: page,
      wordIndexOnPage: wordOnPage,
      wordText: word,
    );

    _errorNotifier.value = null;

    if (_phaseNotifier.value == _SelectionPhase.start) {
      _startNotifier.value = selection;
    } else {
      _endNotifier.value = selection;
    }

    _animateButtonIfNeeded();
  }

  /// Find the 0-indexed word position on the given page (O(1) boundary lookup).
  ///
  /// TODO(P-8): Returns the *first* occurrence of [targetWord] on the page.
  /// If a common word like \"the\" appears multiple times, this may select
  /// the wrong instance. A proper fix requires positional data from the
  /// text selection callback to disambiguate which occurrence was tapped.
  int _findWordIndexOnPage(int page, String targetWord) {
    final boundary = _boundaryByPage[page];
    if (boundary == null) return 0;

    final pageStart = boundary.startWordIndex;
    final pageEnd = _pageEndWordIndex[page] ?? _allWords.length;

    for (var i = pageStart; i < pageEnd; i++) {
      if (i < _allWords.length && _allWords[i] == targetWord) {
        return i - pageStart;
      }
    }
    return 0;
  }

  /// Animate the action button only when it first appears (not on every drag).
  void _animateButtonIfNeeded() {
    if (_buttonAnimController.isCompleted ||
        _buttonAnimController.isDismissed) {
      final reducedMotion = isReducedMotion(context);
      if (!reducedMotion) {
        _buttonAnimController.forward(from: 0);
      } else {
        _buttonAnimController.value = 1.0;
      }
    }
  }

  void _setStart() {
    if (_startNotifier.value == null) return;
    _phaseNotifier.value = _SelectionPhase.end;
    _errorNotifier.value = null;
    _buttonAnimController.reset();
  }

  Future<void> _setEnd() async {
    final start = _startNotifier.value;
    final end = _endNotifier.value;
    if (start == null || end == null) return;

    // Validate: end must be after start.
    if (end.page < start.page) {
      _errorNotifier.value = 'End page must be on or after start page';
      return;
    }
    if (end.page == start.page &&
        end.wordIndexOnPage <= start.wordIndexOnPage) {
      _errorNotifier.value =
          'End word must be after start word on the same page';
      return;
    }

    // Build the ReadingRange.
    final range = ReadingRange(
      startPage: start.page,
      startWordIndexOnPage: start.wordIndexOnPage,
      startWordAnchor: start.wordText,
      endPage: end.page,
      endWordIndexOnPage: end.wordIndexOnPage,
      endWordAnchor: end.wordText,
    );

    // Resolve global indices.
    final resolved = resolveAndValidateRange(range, _pageBoundaries, _allWords);
    if (resolved == null) {
      _errorNotifier.value =
          'Could not resolve range — try re-extracting the PDF';
      return;
    }

    // Check for existing progress (Case 5).
    final config = ref.read(configProvider).valueOrNull ?? const AppConfig();
    final bookmark = config.bookmarks[widget.filePath];
    if (bookmark != null &&
        bookmark.wordIndex > 0 &&
        bookmark.readingRange != null) {
      final confirmed = await showRangeConfirmationModal(
        context: context,
        currentPage: pageForWordIndex(bookmark.wordIndex, _pageBoundaries) + 1,
        currentWord: bookmark.wordIndex < _allWords.length
            ? _allWords[bookmark.wordIndex]
            : '',
      );
      if (!confirmed) return;
    }

    // Save the range and reset position to rangeStart.
    final newBookmark = (bookmark ?? const BookmarkData(wordIndex: 0)).copyWith(
      readingRange: resolved,
      wordIndex: resolved.resolvedStartWordIndex,
      timestamp: DateTime.now(),
    );
    await ref
        .read(configProvider.notifier)
        .updateBookmark(widget.filePath, newBookmark);

    if (mounted) {
      context.go(
        Uri(
          path: '/read',
          queryParameters: {'path': widget.filePath},
        ).toString(),
      );
    }
  }

  Future<void> _clearRange() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _ClearRangeDialog(),
    );
    if (confirmed != true || !mounted) return;

    final config = ref.read(configProvider).valueOrNull ?? const AppConfig();
    final bookmark = config.bookmarks[widget.filePath];
    if (bookmark != null) {
      final updated = bookmark.copyWith(clearReadingRange: true);
      await ref
          .read(configProvider.notifier)
          .updateBookmark(widget.filePath, updated);
    }

    if (mounted) context.pop();
  }

  Future<bool> _onWillPop() async {
    final hasPartial =
        _startNotifier.value != null || _endNotifier.value != null;
    if (hasPartial && !_hasExistingRange) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => _DiscardDialog(),
      );
      return discard ?? false;
    }
    return true;
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(
              Icons.arrow_back,
              color: SpeedyBoyTokens.shellTextPrimary,
            ),
            onPressed: () async {
              final canPop = await _onWillPop();
              if (canPop && mounted) context.pop();
            },
          ),
          Expanded(
            child: ValueListenableBuilder<_SelectionPhase>(
              valueListenable: _phaseNotifier,
              builder: (context, phase, _) {
                return Text(
                  phase == _SelectionPhase.start
                      ? 'Tap your starting word'
                      : 'Tap your ending word',
                  style: SpeedyBoyTypography.title,
                  textAlign: TextAlign.center,
                );
              },
            ),
          ),
          if (_hasExistingRange)
            TextButton(
              onPressed: _clearRange,
              child: Text(
                'Clear Range',
                style: SpeedyBoyTypography.caption.copyWith(
                  color: SpeedyBoyTokens.shellError,
                ),
              ),
            )
          else
            const SizedBox(width: 48),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final canPop = await _onWillPop();
        if (canPop && context.mounted) context.pop();
      },
      child: Scaffold(
        backgroundColor: SpeedyBoyTokens.shellBase,
        body: SafeArea(
          child: Column(
            children: [
              // ── Header ──
              _buildHeader(),

              // ── PDF Viewer (isolated from controls) ──
              Expanded(
                child: RepaintBoundary(
                  child: PdfViewer.file(
                    widget.filePath,
                    controller: _pdfController,
                    params: PdfViewerParams(
                      textSelectionParams: PdfTextSelectionParams(
                        enabled: true,
                        onTextSelectionChange: _onTextSelectionChanged,
                      ),
                      onPageChanged: (pageNumber) {
                        if (pageNumber != null) {
                          _currentPageNotifier.value = pageNumber;
                          if (_pdfController.isReady) {
                            _totalPagesNotifier.value =
                                _pdfController.pageCount;
                          }
                        }
                      },
                      onViewerReady: (doc, controller) {
                        _totalPagesNotifier.value = controller.pageCount;
                        _currentPageNotifier.value = controller.pageNumber ?? 1;
                      },
                    ),
                  ),
                ),
              ),

              // ── Bottom Controls (self-updating via ListenableBuilder) ──
              _BottomControls(
                phaseNotifier: _phaseNotifier,
                startNotifier: _startNotifier,
                endNotifier: _endNotifier,
                errorNotifier: _errorNotifier,
                currentPageNotifier: _currentPageNotifier,
                totalPagesNotifier: _totalPagesNotifier,
                onSetStart: _setStart,
                onSetEnd: _setEnd,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Bottom controls (self-updating, never rebuilds the PDF viewer) ──────────

class _BottomControls extends StatelessWidget {
  const _BottomControls({
    required this.phaseNotifier,
    required this.startNotifier,
    required this.endNotifier,
    required this.errorNotifier,
    required this.currentPageNotifier,
    required this.totalPagesNotifier,
    required this.onSetStart,
    required this.onSetEnd,
  });

  final ValueNotifier<_SelectionPhase> phaseNotifier;
  final ValueNotifier<_WordSelection?> startNotifier;
  final ValueNotifier<_WordSelection?> endNotifier;
  final ValueNotifier<String?> errorNotifier;
  final ValueNotifier<int> currentPageNotifier;
  final ValueNotifier<int> totalPagesNotifier;
  final VoidCallback onSetStart;
  final VoidCallback onSetEnd;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        phaseNotifier,
        startNotifier,
        endNotifier,
        errorNotifier,
        currentPageNotifier,
        totalPagesNotifier,
      ]),
      builder: (context, _) {
        final isStartPhase = phaseNotifier.value == _SelectionPhase.start;
        final currentSelection = isStartPhase
            ? startNotifier.value
            : endNotifier.value;
        final hasSelection = currentSelection != null;
        final totalPages = totalPagesNotifier.value;
        final currentPage = currentPageNotifier.value;
        final errorMessage = errorNotifier.value;
        final startSel = startNotifier.value;
        final endSel = endNotifier.value;

        return Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Page indicator pill.
              if (totalPages > 0)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  decoration: SpeedyBoyDecorations.pillDecoration(
                    SpeedyBoySurface.shell,
                  ),
                  child: Text(
                    'Page $currentPage of $totalPages',
                    style: SpeedyBoyTypography.caption,
                  ),
                ),

              // Selection info.
              if (startSel != null && isStartPhase)
                _SelectionLabel(
                  label: 'Start',
                  page: startSel.page + 1,
                  word: startSel.wordText,
                  color: SpeedyBoyTokens.shellAccent,
                ),
              if (endSel != null && !isStartPhase) ...[
                if (startSel != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: _SelectionLabel(
                      label: 'Start',
                      page: startSel.page + 1,
                      word: startSel.wordText,
                      color: SpeedyBoyTokens.shellAccent,
                    ),
                  ),
                _SelectionLabel(
                  label: 'End',
                  page: endSel.page + 1,
                  word: endSel.wordText,
                  color: SpeedyBoyTokens.shellReady,
                ),
              ],

              // Error message.
              if (errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    errorMessage,
                    style: SpeedyBoyTypography.caption.copyWith(
                      color: SpeedyBoyTokens.shellError,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),

              const SizedBox(height: 12),

              // Action button.
              SizedBox(
                width: double.infinity,
                child: GestureDetector(
                  onTap: hasSelection
                      ? (isStartPhase ? onSetStart : onSetEnd)
                      : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: hasSelection
                        ? SpeedyBoyDecorations.pillDecoration(
                            SpeedyBoySurface.shell,
                          )
                        : SpeedyBoyDecorations.insetDecoration(
                            SpeedyBoySurface.shell,
                            borderRadius: 999,
                          ),
                    child: Text(
                      isStartPhase ? 'Set Start' : 'Set End',
                      style: SpeedyBoyTypography.title.copyWith(
                        color: hasSelection
                            ? SpeedyBoyTokens.shellAccent
                            : SpeedyBoyTokens.shellTextSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Selection label ─────────────────────────────────────────────────────────

class _SelectionLabel extends StatelessWidget {
  const _SelectionLabel({
    required this.label,
    required this.page,
    required this.word,
    required this.color,
  });

  final String label;
  final int page;
  final String word;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 8),
        Text(
          "$label: page $page, '$word'",
          style: SpeedyBoyTypography.caption.copyWith(
            color: SpeedyBoyTokens.shellTextPrimary,
          ),
        ),
      ],
    );
  }
}

// ── Discard dialog ──────────────────────────────────────────────────────────

class _DiscardDialog extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(32),
        padding: const EdgeInsets.all(24),
        decoration: SpeedyBoyDecorations.raisedDecoration(
          SpeedyBoySurface.shell,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Discard selection?', style: SpeedyBoyTypography.title),
            const SizedBox(height: 16),
            Text(
              'Your partial selection will be lost.',
              style: SpeedyBoyTypography.body.copyWith(
                color: SpeedyBoyTokens.shellTextSecondary,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(false),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    decoration: SpeedyBoyDecorations.pillDecoration(
                      SpeedyBoySurface.shell,
                    ),
                    child: const Text(
                      'Cancel',
                      style: SpeedyBoyTypography.body,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(true),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    decoration: SpeedyBoyDecorations.pillDecoration(
                      SpeedyBoySurface.shell,
                    ),
                    child: Text(
                      'Discard',
                      style: SpeedyBoyTypography.body.copyWith(
                        color: SpeedyBoyTokens.shellError,
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
}

// ── Clear range dialog ──────────────────────────────────────────────────────

class _ClearRangeDialog extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(32),
        padding: const EdgeInsets.all(24),
        decoration: SpeedyBoyDecorations.raisedDecoration(
          SpeedyBoySurface.shell,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Clear reading range?',
              style: SpeedyBoyTypography.title,
            ),
            const SizedBox(height: 16),
            Text(
              'This will restore full-document reading.',
              style: SpeedyBoyTypography.body.copyWith(
                color: SpeedyBoyTokens.shellTextSecondary,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(false),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    decoration: SpeedyBoyDecorations.pillDecoration(
                      SpeedyBoySurface.shell,
                    ),
                    child: const Text(
                      'Cancel',
                      style: SpeedyBoyTypography.body,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(true),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    decoration: SpeedyBoyDecorations.pillDecoration(
                      SpeedyBoySurface.shell,
                    ),
                    child: Text(
                      'Clear',
                      style: SpeedyBoyTypography.body.copyWith(
                        color: SpeedyBoyTokens.shellError,
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
}
