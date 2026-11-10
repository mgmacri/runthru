import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:runthru/design/design.dart';

/// What a [ChapterTitleCard] announces.
class ChapterAnnouncement {
  /// Creates an announcement.
  const ChapterAnnouncement({
    required this.headline,
    this.overline = '',
    this.groupTitle,
    this.subtitle,
    this.position,
    this.minutes,
    this.skippedNote,
  });

  /// The largest line: the chapter title, or "Chapter 3" when the chapter
  /// has no other name.
  final String headline;

  /// The small line above it ("Chapter 3"), or empty.
  final String overline;

  /// The part this chapter opens ("Part Two"), if any.
  final String? groupTitle;

  /// A second heading line, if the chapter has one.
  final String? subtitle;

  /// Where the chapter sits in the book ("3 of 12"), if known.
  final String? position;

  /// Reading time of the chapter at the current speed, if known.
  final int? minutes;

  /// Shown when a new book opened past its front matter: what was skipped
  /// ("Skipped the front matter · 12 min"). Offers the way back.
  final String? skippedNote;

  /// What a screen reader hears.
  String get spokenLabel {
    final parts = <String>[
      if (groupTitle != null && groupTitle!.isNotEmpty) groupTitle!,
      if (overline.isNotEmpty) overline,
      headline,
      if (subtitle != null && subtitle!.isNotEmpty) subtitle!,
      if (minutes != null)
        minutes! <= 1 ? 'About a minute' : 'About $minutes minutes',
    ];
    return parts.join('. ');
  }
}

/// Announces a chapter before its first word.
///
/// The label tracks in, a rule draws out from the centre, the title's words
/// rise one after another, then the card lifts away and reading begins. It
/// leaves on its own after a hold that grows with the title's length; a tap
/// starts reading at once.
///
/// With reduced motion the card appears whole, holds, and disappears: no
/// movement, same timing.
class ChapterTitleCard extends StatefulWidget {
  /// Creates a title card.
  const ChapterTitleCard({
    super.key,
    required this.announcement,
    required this.onDone,
    this.onReadFromStart,
    this.insets = EdgeInsets.zero,
  });

  /// Space taken by the reader's header (top) and playback tray (bottom).
  /// The card covers the whole stage; its content keeps clear of these.
  final EdgeInsets insets;

  /// What to announce.
  final ChapterAnnouncement announcement;

  /// Called once, when the card has left (by time or by tap).
  final VoidCallback onDone;

  /// Called when the reader asks for the skipped front matter instead.
  /// Only offered when [ChapterAnnouncement.skippedNote] is set.
  final VoidCallback? onReadFromStart;

  /// Key of the title text (for tests).
  static const Key titleKey = ValueKey('chapter-title-card-title');

  /// Key of the "read from the start" action (for tests).
  static const Key readFromStartKey = ValueKey('chapter-title-card-from-start');

  /// How long the card holds for a title of [titleWords] words.
  static Duration holdFor(int titleWords, {bool hasSkippedNote = false}) {
    final extra = hasSkippedNote
        ? RunThruTiming.titleCardSkippedNoteHold.inMilliseconds
        : 0;
    final ms =
        RunThruTiming.titleCardHold.inMilliseconds +
        RunThruTiming.titleCardHoldPerWord.inMilliseconds * titleWords +
        extra;
    final max = RunThruTiming.titleCardMaxHold.inMilliseconds + extra;
    return Duration(milliseconds: ms.clamp(0, max));
  }

  @override
  State<ChapterTitleCard> createState() => _ChapterTitleCardState();
}

class _ChapterTitleCardState extends State<ChapterTitleCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late List<String> _titleWords;
  bool _reduced = false;
  bool _configured = false;
  bool _finished = false;

  // Timeline, in milliseconds from the start.
  late int _enterMs;
  late int _holdMs;
  late int _exitMs;

  int get _totalMs => _enterMs + _holdMs + _exitMs;

  // Beats of the timeline, built once the timeline is known.
  final List<CurvedAnimation> _curves = [];
  late Animation<double> _wash;
  late Animation<double> _glow;
  late Animation<double> _overline;
  late Animation<double> _rule;
  late Animation<double> _subtitle;
  late Animation<double> _meta;
  late Animation<double> _hold;
  late Animation<double> _exit;
  late List<Animation<double>> _words;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
    _titleWords = _splitWords(widget.announcement.headline);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_configured) return;
    _configured = true;
    _reduced = isReducedMotion(context);
    final a = widget.announcement;
    final spoken =
        _titleWords.length +
        _splitWords(a.subtitle ?? '').length +
        _splitWords(a.overline).length;
    _enterMs = _reduced
        ? 0
        : RunThruTiming.titleCardEnter.inMilliseconds +
              RunThruTiming.titleWordStagger.inMilliseconds *
                  math.max(0, _titleWords.length - 1);
    // Screen-reader users need the announcement to finish being spoken.
    final spokenFactor = MediaQuery.of(context).accessibleNavigation ? 2 : 1;
    _holdMs =
        ChapterTitleCard.holdFor(
          spoken,
          hasSkippedNote: a.skippedNote != null,
        ).inMilliseconds *
        spokenFactor;
    _exitMs = _reduced ? 0 : RunThruTiming.titleCardExit.inMilliseconds;
    _controller.duration = Duration(milliseconds: math.max(1, _totalMs));

    final exitStart = _enterMs + _holdMs;
    final stagger = RunThruTiming.titleWordStagger.inMilliseconds;
    _wash = _span(0, 220);
    _glow = _span(0, 900, curve: Curves.easeOut);
    _overline = _span(60, 480);
    _rule = _span(180, 640);
    _words = [
      for (var i = 0; i < _titleWords.length; i++)
        _span(260 + i * stagger, 260 + i * stagger + 460),
    ];
    _subtitle = _span(_enterMs - 320, _enterMs + 80);
    _meta = _span(_enterMs - 240, _enterMs + 160);
    // The hold hairline and the exit are motion: absent when reduced.
    _hold = _reduced
        ? const AlwaysStoppedAnimation(0)
        : _span(_enterMs, exitStart, curve: Curves.linear);
    _exit = _reduced
        ? const AlwaysStoppedAnimation(0)
        : _span(exitStart, _totalMs, curve: Curves.easeInCubic);

    _controller
      ..addStatusListener(_onStatus)
      ..forward();
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) _finish();
  }

  void _finish() {
    if (_finished) return;
    _finished = true;
    widget.onDone();
  }

  /// Leaves now: plays only the exit.
  void _skip() {
    if (_finished) return;
    HapticFeedback.selectionClick();
    final exitStart = (_enterMs + _holdMs) / _totalMs;
    if (_reduced || _exitMs == 0) {
      _controller.stop();
      _finish();
      return;
    }
    if (_controller.value < exitStart) {
      _controller.forward(from: exitStart);
    }
  }

  @override
  void dispose() {
    for (final curve in _curves) {
      curve.dispose();
    }
    _controller.dispose();
    super.dispose();
  }

  static List<String> _splitWords(String text) =>
      text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

  /// An eased 0→1 over [startMs]..[endMs] of the timeline. Under reduced
  /// motion everything is simply present.
  Animation<double> _span(
    int startMs,
    int endMs, {
    Curve curve = Curves.easeOutCubic,
  }) {
    if (_reduced || _totalMs <= 0 || endMs <= startMs) {
      return const AlwaysStoppedAnimation(1);
    }
    final animation = CurvedAnimation(
      parent: _controller,
      curve: Interval(
        (startMs / _totalMs).clamp(0.0, 1.0),
        (endMs / _totalMs).clamp(0.0, 1.0),
        curve: curve,
      ),
    );
    _curves.add(animation);
    return animation;
  }

  double _titleSize(double width) {
    final chars = widget.announcement.headline.length;
    final base = chars <= 14
        ? 40.0
        : chars <= 28
        ? 34.0
        : chars <= 56
        ? 28.0
        : 23.0;
    // Narrow screens and split-screen windows scale the title down.
    return (base * (width / 380).clamp(0.72, 1.15)).clamp(20.0, 46.0);
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.announcement;
    final wash = _wash;
    final glow = _glow;
    final overline = _overline;
    final rule = _rule;
    final meta = _meta;
    final subtitle = _subtitle;
    final exit = _exit;
    final hold = _hold;

    // The announcement is one node and the ways out are their own: merged,
    // the whole card would read as a button named after the chapter.
    return Semantics(
      container: true,
      explicitChildNodes: true,
      liveRegion: true,
      label: a.spokenLabel,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          final insets = widget.insets;
          final clearHeight = size.height - insets.vertical;
          final compact = clearHeight < 420;
          final titleStyle = RunThruTypography.chapterTitle.copyWith(
            fontSize: _titleSize(size.width) * (compact ? 0.82 : 1),
          );
          final wordGap = titleStyle.fontSize! * 0.26;

          return FadeTransition(
            opacity: ReverseAnimation(exit),
            child: Stack(
              children: [
                // Wash: the last word of the previous chapter leaves.
                Positioned.fill(
                  child: FadeTransition(
                    opacity: wash,
                    child: const ColoredBox(
                      color: RunThruTokens.stageMomentWash,
                    ),
                  ),
                ),
                // Bloom behind the title.
                Positioned.fill(
                  child: IgnorePointer(
                    child: ExcludeSemantics(
                      child: FadeTransition(
                        opacity: glow,
                        child: ScaleTransition(
                          scale: Tween<double>(
                            begin: 0.7,
                            end: 1,
                          ).animate(glow),
                          child: const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: RadialGradient(
                                center: Alignment(0, -0.14),
                                radius: 0.7,
                                colors: [
                                  RunThruTokens.stageMomentGlow,
                                  RunThruTokens.stageMomentGlowClear,
                                ],
                                stops: [0, 1],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // Tap anywhere to start reading now.
                Positioned.fill(
                  child: Semantics(
                    container: true,
                    button: true,
                    label: 'Start reading',
                    onTap: _skip,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      excludeFromSemantics: true,
                      onTap: _skip,
                    ),
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: ExcludeSemantics(
                      child: ScaleTransition(
                        scale: Tween<double>(begin: 1, end: 1.06).animate(exit),
                        child: Align(
                          alignment: Alignment(0, compact ? 0 : -0.14),
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              28,
                              insets.top,
                              28,
                              insets.bottom,
                            ),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 440),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: math.min(
                                      440,
                                      math.max(160, size.width - 56),
                                    ),
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (a.groupTitle != null &&
                                          a.groupTitle!.isNotEmpty) ...[
                                        FadeTransition(
                                          opacity: overline,
                                          child: Text(
                                            a.groupTitle!.toUpperCase(),
                                            textAlign: TextAlign.center,
                                            textScaler: TextScaler.noScaling,
                                            style: RunThruTypography
                                                .chapterOverline
                                                .copyWith(
                                                  color: RunThruTokens
                                                      .shellInkSoft,
                                                  fontSize: 11,
                                                ),
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                      ],
                                      if (a.overline.isNotEmpty)
                                        _TrackingLabel(
                                          text: a.overline.toUpperCase(),
                                          animation: overline,
                                        ),
                                      SizedBox(height: compact ? 10 : 14),
                                      SizedBox(
                                        width: 150,
                                        height: 12,
                                        child: CustomPaint(
                                          painter: _RulePainter(rule),
                                        ),
                                      ),
                                      SizedBox(height: compact ? 12 : 18),
                                      Wrap(
                                        key: ChapterTitleCard.titleKey,
                                        alignment: WrapAlignment.center,
                                        spacing: wordGap,
                                        runSpacing: titleStyle.fontSize! * 0.08,
                                        children: [
                                          for (
                                            var i = 0;
                                            i < _titleWords.length;
                                            i++
                                          )
                                            _RisingWord(
                                              word: _titleWords[i],
                                              style: titleStyle,
                                              animation: _words[i],
                                            ),
                                        ],
                                      ),
                                      if (a.subtitle != null &&
                                          a.subtitle!.isNotEmpty) ...[
                                        SizedBox(height: compact ? 8 : 12),
                                        FadeTransition(
                                          opacity: subtitle,
                                          child: Text(
                                            a.subtitle!,
                                            textAlign: TextAlign.center,
                                            maxLines: 3,
                                            overflow: TextOverflow.ellipsis,
                                            textScaler: TextScaler.noScaling,
                                            style: RunThruTypography
                                                .chapterSubtitle,
                                          ),
                                        ),
                                      ],
                                      if (a.position != null ||
                                          a.minutes != null) ...[
                                        SizedBox(height: compact ? 14 : 22),
                                        FadeTransition(
                                          opacity: meta,
                                          child: _MetaRow(
                                            position: a.position,
                                            minutes: a.minutes,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // Skipped front matter: the way back, and the hold timer.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: insets.bottom + (compact ? 6 : 14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (a.skippedNote != null &&
                          widget.onReadFromStart != null)
                        FadeTransition(
                          opacity: meta,
                          child: _SkippedNote(
                            key: ChapterTitleCard.readFromStartKey,
                            note: a.skippedNote!,
                            onReadFromStart: () {
                              if (_finished) return;
                              _finished = true;
                              _controller.stop();
                              widget.onReadFromStart!();
                            },
                          ),
                        ),
                      if (!_reduced) ...[
                        const SizedBox(height: 12),
                        IgnorePointer(
                          child: ExcludeSemantics(
                            child: _HoldHairline(animation: hold),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// The overline: letter-spacing settles from wide to its resting value.
class _TrackingLabel extends StatelessWidget {
  const _TrackingLabel({required this.text, required this.animation});

  final String text;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    const style = RunThruTypography.chapterOverline;
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = animation.value;
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Text(
            text,
            textAlign: TextAlign.center,
            maxLines: 2,
            textScaler: TextScaler.noScaling,
            style: style.copyWith(
              letterSpacing: style.letterSpacing! + (1 - t) * 6,
            ),
          ),
        );
      },
    );
  }
}

/// One title word: rises a little and fades in.
class _RisingWord extends StatelessWidget {
  const _RisingWord({
    required this.word,
    required this.style,
    required this.animation,
  });

  final String word;
  final TextStyle style;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.42),
          end: Offset.zero,
        ).animate(animation),
        child: Text(word, style: style, textScaler: TextScaler.noScaling),
      ),
    );
  }
}

/// A rule that draws outward from a centre diamond.
class _RulePainter extends CustomPainter {
  _RulePainter(this.animation) : super(repaint: animation);

  final Animation<double> animation;

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value.clamp(0.0, 1.0);
    if (t <= 0) return;
    final centre = Offset(size.width / 2, size.height / 2);
    final half = size.width / 2;
    final line = Paint()
      ..color = RunThruTokens.shellTeal.withValues(alpha: 0.55 * t)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    const gap = 9.0;
    final reach = gap + (half - gap) * t;
    canvas
      ..drawLine(centre.translate(-gap, 0), centre.translate(-reach, 0), line)
      ..drawLine(centre.translate(gap, 0), centre.translate(reach, 0), line);

    // The diamond pops slightly past its size, then settles.
    final pop = t < 0.6 ? t / 0.6 * 1.25 : 1.25 - (t - 0.6) / 0.4 * 0.25;
    final r = 3.6 * pop;
    final diamond = Path()
      ..moveTo(centre.dx, centre.dy - r)
      ..lineTo(centre.dx + r, centre.dy)
      ..lineTo(centre.dx, centre.dy + r)
      ..lineTo(centre.dx - r, centre.dy)
      ..close();
    canvas.drawPath(diamond, Paint()..color = RunThruTokens.shellTeal);
  }

  @override
  bool shouldRepaint(_RulePainter oldDelegate) =>
      oldDelegate.animation != animation;
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({this.position, this.minutes});

  final String? position;
  final int? minutes;

  @override
  Widget build(BuildContext context) {
    final style = RunThruTypography.statusPill.copyWith(fontSize: 12);
    final parts = <String>[
      if (position != null) position!,
      if (minutes != null) minutes! <= 1 ? '1 min' : '$minutes min',
    ];
    return DecoratedBox(
      decoration: RunThruDecorations.statusPill(emphasized: true),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        child: Text(
          parts.join('  ·  '),
          style: style,
          textScaler: TextScaler.noScaling,
        ),
      ),
    );
  }
}

/// "Skipped the front matter · Read from the start".
class _SkippedNote extends StatelessWidget {
  const _SkippedNote({
    super.key,
    required this.note,
    required this.onReadFromStart,
  });

  final String note;
  final VoidCallback onReadFromStart;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Semantics(
        container: true,
        button: true,
        label: '$note. Read from the start instead',
        onTap: onReadFromStart,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTap: onReadFromStart,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: RunThruA11y.minTapTarget,
              maxWidth: 420,
            ),
            child: DecoratedBox(
              decoration: RunThruDecorations.raisedDecoration(
                RunThruSurface.stage,
                size: RunThruShadowSize.small,
                borderRadius: 999,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 10,
                ),
                // Wraps: on a narrow screen the action drops under the note.
                child: ExcludeSemantics(
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    runAlignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 10,
                    runSpacing: 2,
                    children: [
                      Text(
                        note,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: RunThruTypography.metadata.copyWith(
                          color: RunThruTokens.shellInkSoft,
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Flexible: large system text must not push
                          // the chevron off the pill.
                          Flexible(
                            child: Text(
                              'Read from the start',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: RunThruTypography.metadata.copyWith(
                                color: RunThruTokens.shellTealDeep,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 2),
                          const Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                            color: RunThruTokens.shellTealDeep,
                          ),
                        ],
                      ),
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

/// A hairline that fills while the card holds: how long until reading
/// starts on its own.
class _HoldHairline extends StatelessWidget {
  const _HoldHairline({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 64,
      height: 3,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: ColoredBox(
          color: RunThruTokens.stageDarkShadow,
          child: AnimatedBuilder(
            animation: animation,
            builder: (context, _) => FractionallySizedBox(
              alignment: AlignmentDirectional.centerStart,
              widthFactor: animation.value.clamp(0.0, 1.0),
              child: const ColoredBox(color: RunThruTokens.shellTeal),
            ),
          ),
        ),
      ),
    );
  }
}

/// Announces a heading inside a chapter: the whole line at once, briefly,
/// instead of one word at a time.
///
/// With reduced motion it appears and disappears without movement.
class SubHeadingCard extends StatefulWidget {
  /// Creates a sub-heading announcement.
  const SubHeadingCard({
    super.key,
    required this.text,
    required this.fontFamily,
    required this.onDone,
  });

  /// The heading.
  final String text;

  /// The reading font, so the heading belongs to the text.
  final String fontFamily;

  /// Called once, when the announcement has left.
  final VoidCallback onDone;

  /// How long a heading of [words] words holds.
  static Duration holdFor(int words) {
    final ms =
        RunThruTiming.subHeadingHold.inMilliseconds +
        RunThruTiming.subHeadingHoldPerWord.inMilliseconds * words;
    return Duration(
      milliseconds: ms.clamp(0, RunThruTiming.titleCardMaxHold.inMilliseconds),
    );
  }

  @override
  State<SubHeadingCard> createState() => _SubHeadingCardState();
}

class _SubHeadingCardState extends State<SubHeadingCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _configured = false;
  bool _reduced = false;
  bool _finished = false;
  int _enterMs = 0;
  int _holdMs = 0;
  int _exitMs = 0;
  final List<CurvedAnimation> _curves = [];
  late Animation<double> _enter;
  late Animation<double> _exit;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_configured) return;
    _configured = true;
    _reduced = isReducedMotion(context);
    final words = widget.text.split(RegExp(r'\s+')).length;
    _enterMs = _reduced ? 0 : RunThruTiming.subHeadingEnter.inMilliseconds;
    _exitMs = _reduced ? 0 : RunThruTiming.subHeadingExit.inMilliseconds;
    _holdMs =
        SubHeadingCard.holdFor(words).inMilliseconds *
        (MediaQuery.of(context).accessibleNavigation ? 2 : 1);
    final total = _enterMs + _holdMs + _exitMs;
    _controller.duration = Duration(milliseconds: total);
    if (_reduced) {
      _enter = const AlwaysStoppedAnimation(1);
      _exit = const AlwaysStoppedAnimation(0);
    } else {
      final enter = CurvedAnimation(
        parent: _controller,
        curve: Interval(0, _enterMs / total, curve: Curves.easeOutCubic),
      );
      final exit = CurvedAnimation(
        parent: _controller,
        curve: Interval((_enterMs + _holdMs) / total, 1, curve: Curves.easeIn),
      );
      _curves
        ..add(enter)
        ..add(exit);
      _enter = enter;
      _exit = exit;
    }
    _controller
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _finish();
      })
      ..forward();
  }

  void _finish() {
    if (_finished) return;
    _finished = true;
    widget.onDone();
  }

  @override
  void dispose() {
    for (final curve in _curves) {
      curve.dispose();
    }
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enter = _enter;
    final exit = _exit;
    final style = TextStyle(
      fontFamily: widget.fontFamily,
      fontSize: 26,
      fontWeight: FontWeight.w700,
      height: 1.25,
      color: RunThruTokens.stageText,
    );
    return Semantics(
      container: true,
      explicitChildNodes: true,
      liveRegion: true,
      label: widget.text,
      child: Stack(
        children: [
          Positioned.fill(
            child: FadeTransition(
              opacity: ReverseAnimation(exit),
              child: FadeTransition(
                opacity: enter,
                child: const ColoredBox(color: RunThruTokens.stageMomentWash),
              ),
            ),
          ),
          Positioned.fill(
            child: Semantics(
              container: true,
              button: true,
              label: 'Continue reading',
              onTap: _finish,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                excludeFromSemantics: true,
                onTap: () {
                  _controller.stop();
                  _finish();
                },
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: FadeTransition(
                  opacity: ReverseAnimation(exit),
                  child: FadeTransition(
                    opacity: enter,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.04),
                        end: Offset.zero,
                      ).animate(enter),
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 420),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  widget.text,
                                  textAlign: TextAlign.center,
                                  maxLines: 5,
                                  overflow: TextOverflow.ellipsis,
                                  textScaler: TextScaler.noScaling,
                                  style: style,
                                ),
                                const SizedBox(height: 14),
                                SizedBox(
                                  width: 44,
                                  height: 3,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: RunThruTokens.shellTeal.withValues(
                                        alpha: 0.7,
                                      ),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
