import 'package:flutter/material.dart';
import 'package:runthru/core/book_structure.dart';
import 'package:runthru/core/time_left.dart';
import 'package:runthru/design/design.dart';
import 'package:runthru/features/reading/chapter_flow.dart';

/// Shows the book's contents and returns the section the reader picked, or
/// null when the sheet was dismissed.
///
/// Chapters are listed with their reading time; the ones already read are
/// ticked and the current one shows how far into it the reader is. Front
/// and back matter sit in their own groups, folded away until asked for.
Future<BookSection?> showContentsSheet(
  BuildContext context, {
  required BookStructure structure,
  required int currentWord,
  required int wpm,
  required String bookTitle,
}) {
  return showModalBottomSheet<BookSection>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: RunThruTokens.tourScrim.withValues(alpha: 0.32),
    builder: (context) => ContentsSheet(
      structure: structure,
      currentWord: currentWord,
      wpm: wpm,
      bookTitle: bookTitle,
    ),
  );
}

/// The contents list. See [showContentsSheet].
class ContentsSheet extends StatefulWidget {
  /// Creates the sheet.
  const ContentsSheet({
    super.key,
    required this.structure,
    required this.currentWord,
    required this.wpm,
    required this.bookTitle,
  });

  /// The book's sections.
  final BookStructure structure;

  /// Document word index the reader is at.
  final int currentWord;

  /// Current reading speed, for the time estimates.
  final int wpm;

  /// The book's title.
  final String bookTitle;

  /// Height of one chapter row.
  static const double rowExtent = 64;

  @override
  State<ContentsSheet> createState() => _ContentsSheetState();
}

class _ContentsSheetState extends State<ContentsSheet> {
  bool _showFront = false;
  bool _showBack = false;

  /// Whether the list has been moved to the current chapter (once).
  bool _positioned = false;

  BookStructure get _structure => widget.structure;

  late final BookSection _current = _structure.sectionAt(widget.currentWord);
  late final List<BookSection> _front = [
    for (final s in _structure.sections)
      if (s.kind == SectionKind.front) s,
  ];
  late final List<BookSection> _back = [
    for (final s in _structure.sections)
      if (s.kind == SectionKind.back) s,
  ];

  @override
  void initState() {
    super.initState();
    // Open on the part of the book the reader is in.
    _showFront = _current.kind == SectionKind.front;
    _showBack = _current.kind == SectionKind.back;
  }

  /// Scroll so the current chapter sits a couple of rows from the top.
  double _initialOffset() {
    final chapters = _structure.chapters;
    final at = chapters.indexWhere((s) => s.index == _current.index);
    if (at <= 2) return 0;
    final frontRows = _front.isEmpty ? 0 : 1;
    return (at - 2 + frontRows) * ContentsSheet.rowExtent;
  }

  int _minutes(int words) => minutesFor(words, widget.wpm);

  @override
  Widget build(BuildContext context) {
    final chapters = _structure.chapters;
    final done = chapters.where((s) => s.end <= widget.currentWord).length;
    final media = MediaQuery.of(context);
    final frontWords = _front.fold<int>(0, (sum, s) => sum + (s.end - s.start));
    final backWords = _back.fold<int>(0, (sum, s) => sum + (s.end - s.start));

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      minChildSize: 0.4,
      maxChildSize: 0.94,
      builder: (context, controller) {
        // Jump to the current chapter the first time the list is laid out.
        // (The sheet owns [controller]; it is never kept or disposed here.)
        if (!_positioned) {
          _positioned = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || !controller.hasClients) return;
            final target = _initialOffset().clamp(
              0.0,
              controller.position.maxScrollExtent,
            );
            if (target > 0) controller.jumpTo(target);
          });
        }
        return DecoratedBox(
          decoration: const BoxDecoration(
            color: RunThruTokens.shellSand,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: [
              BoxShadow(
                color: RunThruTokens.shellSandDeep,
                offset: Offset(0, -6),
                blurRadius: 24,
              ),
            ],
          ),
          child: Semantics(
            container: true,
            explicitChildNodes: true,
            label: 'Contents',
            child: Column(
              children: [
                const SizedBox(height: 10),
                // Grab handle.
                const ExcludeSemantics(
                  child: SizedBox(
                    width: 44,
                    height: 5,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: RunThruTokens.shellSandDeep,
                        borderRadius: BorderRadius.all(Radius.circular(999)),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 12, 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Semantics(
                              header: true,
                              child: const Text(
                                'Contents',
                                style: RunThruTypography.screenTitle,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              chapters.length >= 2
                                  ? '$done of ${chapters.length} chapters read'
                                  : widget.bookTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: RunThruTypography.metadata,
                            ),
                          ],
                        ),
                      ),
                      Semantics(
                        button: true,
                        label: 'Close contents',
                        onTap: () => Navigator.of(context).pop(),
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          excludeFromSemantics: true,
                          onTap: () => Navigator.of(context).pop(),
                          child: const SizedBox(
                            width: RunThruA11y.minTapTarget,
                            height: RunThruA11y.minTapTarget,
                            child: ExcludeSemantics(
                              child: Icon(
                                Icons.close_rounded,
                                color: RunThruTokens.shellInkSoft,
                                size: 22,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    controller: controller,
                    padding: EdgeInsets.fromLTRB(
                      12,
                      0,
                      12,
                      16 + media.padding.bottom,
                    ),
                    children: [
                      if (_front.isNotEmpty)
                        _GroupRow(
                          label: 'Before the book',
                          detail: formatMinutes(_minutes(frontWords)),
                          expanded: _showFront,
                          onTap: () => setState(() => _showFront = !_showFront),
                        ),
                      if (_showFront)
                        for (final s in _front) _row(s, minor: true),
                      for (final s in chapters) _row(s),
                      if (_back.isNotEmpty)
                        _GroupRow(
                          label: 'After the book',
                          detail: formatMinutes(_minutes(backWords)),
                          expanded: _showBack,
                          onTap: () => setState(() => _showBack = !_showBack),
                        ),
                      if (_showBack)
                        for (final s in _back) _row(s, minor: true),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _row(BookSection section, {bool minor = false}) {
    final isCurrent = section.index == _current.index;
    // Only chapters are ticked off: front and back matter are passed, not
    // necessarily read (a new book opens past its front matter).
    final isDone = !minor && !isCurrent && section.end <= widget.currentWord;
    final span = section.end - section.start;
    final within = isCurrent && span > 0
        ? ((widget.currentWord - section.start) / span).clamp(0.0, 1.0)
        : 0.0;
    return _SectionRow(
      key: ValueKey('contents-row-${section.index}'),
      section: section,
      minutes: _minutes(section.end - section.start),
      isCurrent: isCurrent,
      isDone: isDone,
      progress: within,
      minor: minor,
      fallbackName: section.kind == SectionKind.front
          ? 'Opening pages'
          : section.kind == SectionKind.back
          ? 'Closing pages'
          : _structure.chapters.length <= 1
          ? widget.bookTitle
          : 'Untitled section',
      onTap: () => Navigator.of(context).pop(section),
    );
  }
}

/// A folding group header: "Before the book · 12 min".
class _GroupRow extends StatelessWidget {
  const _GroupRow({
    required this.label,
    required this.detail,
    required this.expanded,
    required this.onTap,
  });

  final String label;
  final String detail;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      expanded: expanded,
      label: '$label, $detail',
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: RunThruA11y.minTapTarget,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: ExcludeSemantics(
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label.toUpperCase(),
                      style: RunThruTypography.sectionLabel.copyWith(
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  Text(detail, style: RunThruTypography.metadata),
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: isReducedMotion(context)
                        ? Duration.zero
                        : RunThruAnimations.dialEmergeDuration,
                    child: const Icon(
                      Icons.expand_more_rounded,
                      size: 20,
                      color: RunThruTokens.shellInkSoft,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One section: a status mark, its label and title, and its reading time.
class _SectionRow extends StatelessWidget {
  const _SectionRow({
    super.key,
    required this.section,
    required this.minutes,
    required this.isCurrent,
    required this.isDone,
    required this.progress,
    required this.minor,
    required this.fallbackName,
    required this.onTap,
  });

  final BookSection section;
  final int minutes;
  final bool isCurrent;
  final bool isDone;

  /// How far into the current section the reader is (0..1).
  final double progress;

  /// Front or back matter: quieter styling.
  final bool minor;
  final String fallbackName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = section.displayName(fallback: fallbackName);
    final headline = section.isTitled ? section.headline : fallbackName;
    final overline = section.overline;
    final status = isCurrent
        ? 'reading now, ${(progress * 100).round()} percent'
        : isDone
        ? 'read'
        : '';
    final time = formatMinutes(minutes);
    final inkColor = minor || isDone
        ? RunThruTokens.shellInkSoft
        : RunThruTokens.shellInk;

    return Semantics(
      button: true,
      selected: isCurrent,
      label: [name, time, if (status.isNotEmpty) status].join(', '),
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: DecoratedBox(
            decoration: isCurrent
                ? RunThruDecorations.designerRaisedSmall(borderRadius: 16)
                : const BoxDecoration(),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: ContentsSheet.rowExtent - 6,
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: ExcludeSemantics(
                  child: Row(
                    children: [
                      _StatusMark(
                        isCurrent: isCurrent,
                        isDone: isDone,
                        progress: progress,
                        minor: minor,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (overline.isNotEmpty)
                              Text(
                                overline.toUpperCase(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: RunThruTypography.tinyLabel.copyWith(
                                  letterSpacing: 1.1,
                                  color: isCurrent
                                      ? RunThruTokens.shellTealDeep
                                      : RunThruTokens.shellInkFaint,
                                ),
                              ),
                            Text(
                              headline,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: RunThruTypography.rowTitle.copyWith(
                                color: inkColor,
                                fontWeight: isCurrent
                                    ? FontWeight.w800
                                    : minor
                                    ? FontWeight.w500
                                    : FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(time, style: RunThruTypography.metadata),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Read (tick), reading now (a ring filled to the progress), or to come.
class _StatusMark extends StatelessWidget {
  const _StatusMark({
    required this.isCurrent,
    required this.isDone,
    required this.progress,
    this.minor = false,
  });

  final bool isCurrent;
  final bool isDone;
  final double progress;

  /// Front or back matter: a plain dot unless it is being read.
  final bool minor;

  @override
  Widget build(BuildContext context) {
    const size = 26.0;
    if (minor && !isCurrent) {
      return const SizedBox(
        width: size,
        height: size,
        child: Center(
          child: SizedBox(
            width: 8,
            height: 8,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: RunThruTokens.shellSandDeep,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      );
    }
    if (isDone) {
      return const SizedBox(
        width: size,
        height: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: RunThruTokens.shellTeal,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.check_rounded,
            size: 16,
            color: RunThruTokens.shellCream,
          ),
        ),
      );
    }
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        value: isCurrent ? progress.clamp(0.04, 1.0) : 0,
        strokeWidth: 3,
        strokeCap: StrokeCap.round,
        backgroundColor: RunThruTokens.shellSandDeep,
        color: RunThruTokens.shellTeal,
      ),
    );
  }
}
