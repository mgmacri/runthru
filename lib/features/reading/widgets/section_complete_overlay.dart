import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:runthru/core/time_left.dart';
import 'package:runthru/design/design.dart';

/// What the reader just finished, and what comes next.
class SectionCompletion {
  /// Creates a completion summary.
  const SectionCompletion({
    required this.headline,
    required this.wordsRead,
    required this.readingTime,
    this.detail,
    this.chapterNumber = 0,
    this.chapterCount = 0,
    this.bookProgress = 0,
    this.nextName,
    this.nextMinutes,
  });

  /// "Chapter 3 complete".
  final String headline;

  /// The chapter's own title, when it has one beside its number.
  final String? detail;

  /// Words read in this chapter this sitting.
  final int wordsRead;

  /// Time spent reading them (paused time excluded).
  final Duration readingTime;

  /// 1-based position of the finished chapter, or 0 when unknown.
  final int chapterNumber;

  /// Chapters in the book, or 0 when unknown.
  final int chapterCount;

  /// How far through the book's text the reader now is (0..1).
  final double bookProgress;

  /// Name of the next chapter ("Chapter 4: The Storm"), if there is one.
  final String? nextName;

  /// Reading time of the next chapter at the current speed.
  final int? nextMinutes;

  /// Average speed over the chapter, or 0 when too little was timed.
  int get wordsPerMinute {
    final seconds = readingTime.inMilliseconds / 1000;
    if (seconds < 5 || wordsRead <= 0) return 0;
    return (wordsRead / (seconds / 60)).round();
  }

  /// What a screen reader hears.
  String get spokenLabel {
    final parts = <String>[
      headline,
      if (detail != null && detail!.isNotEmpty) detail!,
      '$wordsRead words in ${_spokenDuration(readingTime)}',
      if (chapterCount > 0) '$chapterNumber of $chapterCount chapters',
      if (nextName != null) 'Next: $nextName',
    ];
    return parts.join('. ');
  }
}

/// What the reader finished when the book ends.
class BookCompletion {
  /// Creates a book summary.
  const BookCompletion({
    required this.title,
    required this.wordsInBook,
    required this.chapterCount,
    required this.sessionTime,
    this.backMatterMinutes,
  });

  /// The book's title.
  final String title;

  /// Words in the book's text (front and back matter excluded).
  final int wordsInBook;

  /// Chapters in the book, or 0 when it has none.
  final int chapterCount;

  /// Time spent reading this sitting.
  final Duration sessionTime;

  /// Reading time of what follows the last chapter (notes, extras), when
  /// there is something left to read.
  final int? backMatterMinutes;
}

String _spokenDuration(Duration d) {
  final minutes = d.inSeconds ~/ 60;
  if (minutes < 1) return '${d.inSeconds} seconds';
  return minutes == 1 ? '1 minute' : '$minutes minutes';
}

String _clock(Duration d) {
  final minutes = d.inSeconds ~/ 60;
  final seconds = d.inSeconds % 60;
  if (minutes >= 60) {
    return '${minutes ~/ 60}h ${(minutes % 60).toString().padLeft(2, '0')}m';
  }
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

/// "12,345".
String formatCount(int n) {
  final digits = n.abs().toString();
  final out = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}

/// The end of a chapter, marked: a ring closes, a check draws, the badge
/// pops with a burst, the figures count up, and the next chapter is one tap
/// (or a short countdown) away.
///
/// With reduced motion nothing moves and nothing starts on its own: the
/// finished badge, the figures and the two choices are simply shown.
class SectionCompleteOverlay extends StatefulWidget {
  /// Creates the overlay.
  const SectionCompleteOverlay({
    super.key,
    required this.completion,
    required this.onContinue,
    this.onBreak,
    this.autoContinue = true,
  });

  /// What was finished and what is next.
  final SectionCompletion completion;

  /// Go on to the next chapter.
  final VoidCallback onContinue;

  /// Stop here: stay paused at the start of the next chapter. Null hides
  /// the choice (Book mode has nothing to pause).
  final VoidCallback? onBreak;

  /// Whether the next chapter starts by itself after a countdown. Ignored
  /// (off) with reduced motion or a screen reader.
  final bool autoContinue;

  /// Key of the Continue button (for tests).
  static const Key continueKey = ValueKey('section-complete-continue');

  /// Key of the Take a break button (for tests).
  static const Key breakKey = ValueKey('section-complete-break');

  @override
  State<SectionCompleteOverlay> createState() => _SectionCompleteOverlayState();
}

class _SectionCompleteOverlayState extends State<SectionCompleteOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _badge;
  late final AnimationController _burst;
  late final AnimationController _count;
  late final AnimationController _auto;
  late final List<_Particle> _particles;
  bool _configured = false;
  bool _reduced = false;
  bool _left = false;
  bool _popped = false;

  @override
  void initState() {
    super.initState();
    _badge = AnimationController(
      vsync: this,
      duration: RunThruTiming.celebrationBadge,
    );
    _burst = AnimationController(
      vsync: this,
      duration: RunThruTiming.celebrationBurst,
    );
    _count = AnimationController(
      vsync: this,
      duration: RunThruTiming.celebrationCountUp,
    );
    _auto = AnimationController(
      vsync: this,
      duration: RunThruTiming.celebrationAutoContinue,
    );
    _particles = [
      ..._Particle.burst(count: 26, seed: 7),
      ..._Particle.burst(count: 18, seed: 19, delay: 0.1, reach: 0.62),
    ];
    _badge.addListener(_onBadgeTick);
    _auto.addStatusListener((status) {
      if (status == AnimationStatus.completed) _continue();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_configured) return;
    _configured = true;
    final media = MediaQuery.of(context);
    _reduced = isReducedMotion(context);
    if (_reduced) {
      // No motion: show the finished state.
      _badge.duration = Duration.zero;
      _burst.duration = Duration.zero;
      _count.duration = Duration.zero;
      _badge.value = 1;
      _count.value = 1;
      return;
    }
    _badge.forward();
    _count.forward();
    if (widget.autoContinue &&
        !media.accessibleNavigation &&
        widget.completion.nextName != null) {
      // The countdown starts once the badge has landed.
      _badge.addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted && !_left) {
          _auto.forward();
        }
      });
    }
  }

  /// The pop: haptic and burst fire once, as the check lands.
  void _onBadgeTick() {
    if (_popped || _badge.value < _MomentBadge.popAt) return;
    _popped = true;
    HapticFeedback.mediumImpact();
    _burst.forward();
  }

  void _continue() {
    if (_left) return;
    _left = true;
    _auto.stop();
    widget.onContinue();
  }

  void _break() {
    if (_left) return;
    _left = true;
    _auto.stop();
    widget.onBreak?.call();
  }

  /// A touch that is not a button means "let me look": stop the countdown.
  void _holdHere() {
    if (_auto.isAnimating) {
      _auto.stop();
      setState(() {});
    }
  }

  @override
  void dispose() {
    _badge.dispose();
    _burst.dispose();
    _count.dispose();
    _auto.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.completion;
    final hasNext = c.nextName != null;
    return _MomentScaffold(
      spokenLabel: c.spokenLabel,
      onBackgroundTouch: _holdHere,
      summary: (context, compact) => [
        _MomentBadge(
          animation: _badge,
          burst: _burst,
          particles: _particles,
          size: compact ? 68 : 96,
        ),
        SizedBox(height: compact ? 12 : 20),
        Text(
          c.headline,
          textAlign: TextAlign.center,
          style: RunThruTypography.momentHeadline,
        ),
        if (c.detail != null && c.detail!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            c.detail!,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: RunThruTypography.chapterSubtitle,
          ),
        ],
        SizedBox(height: compact ? 12 : 22),
        _StatsRow(
          animation: _count,
          stats: [
            (value: c.wordsRead, text: null, label: 'WORDS'),
            if (c.readingTime.inSeconds >= 5)
              (value: null, text: _clock(c.readingTime), label: 'TIME'),
            if (c.wordsPerMinute > 0)
              (value: c.wordsPerMinute, text: null, label: 'WPM'),
          ],
        ),
        if (c.chapterCount > 0) ...[
          SizedBox(height: compact ? 12 : 22),
          _BookProgress(
            animation: _count,
            done: c.chapterNumber,
            total: c.chapterCount,
            fraction: c.bookProgress,
          ),
        ],
      ],
      actions: (context, compact) => [
        if (hasNext) ...[
          _NextUp(name: c.nextName!, minutes: c.nextMinutes),
          const SizedBox(height: 14),
        ],
        _MomentButton(
          key: SectionCompleteOverlay.continueKey,
          label: 'Continue',
          semanticLabel: hasNext ? 'Continue: ${c.nextName}' : 'Continue',
          icon: Icons.arrow_forward_rounded,
          countdown: _auto,
          onPressed: _continue,
        ),
        const SizedBox(height: 4),
        if (widget.onBreak != null)
          _MomentTextButton(
            key: SectionCompleteOverlay.breakKey,
            label: 'Take a break',
            onPressed: _break,
          ),
      ],
    );
  }
}

/// The end of the book: a larger badge and burst, what was read, and where
/// to go next (the library, the back matter, or the start again).
///
/// With reduced motion nothing moves.
class BookCompleteOverlay extends StatefulWidget {
  /// Creates the overlay.
  const BookCompleteOverlay({
    super.key,
    required this.completion,
    required this.onLibrary,
    required this.onReadAgain,
    this.onKeepReading,
  });

  /// What was finished.
  final BookCompletion completion;

  /// Back to the library.
  final VoidCallback onLibrary;

  /// Start the book again from its first chapter.
  final VoidCallback onReadAgain;

  /// Read on into what follows the last chapter. Null when nothing does.
  final VoidCallback? onKeepReading;

  /// Key of the library button (for tests).
  static const Key libraryKey = ValueKey('book-complete-library');

  /// Key of the keep-reading button (for tests).
  static const Key keepReadingKey = ValueKey('book-complete-keep-reading');

  /// Key of the read-again button (for tests).
  static const Key readAgainKey = ValueKey('book-complete-read-again');

  @override
  State<BookCompleteOverlay> createState() => _BookCompleteOverlayState();
}

class _BookCompleteOverlayState extends State<BookCompleteOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _badge;
  late final AnimationController _burst;
  late final AnimationController _count;
  late final List<_Particle> _particles;
  bool _configured = false;
  bool _popped = false;

  @override
  void initState() {
    super.initState();
    _badge = AnimationController(
      vsync: this,
      duration: RunThruTiming.celebrationBadge,
    );
    // Two waves: the second starts as the first is opening out.
    _burst = AnimationController(
      vsync: this,
      duration: RunThruTiming.celebrationBurst * 1.5,
    );
    _count = AnimationController(
      vsync: this,
      duration: RunThruTiming.celebrationCountUp,
    );
    _particles = [
      ..._Particle.burst(count: 34, seed: 11),
      ..._Particle.burst(count: 26, seed: 23, delay: 0.22, reach: 1.25),
    ];
    _badge.addListener(() {
      if (_popped || _badge.value < _MomentBadge.popAt) return;
      _popped = true;
      HapticFeedback.heavyImpact();
      _burst.forward();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_configured) return;
    _configured = true;
    if (isReducedMotion(context)) {
      _badge.duration = Duration.zero;
      _burst.duration = Duration.zero;
      _count.duration = Duration.zero;
      _badge.value = 1;
      _count.value = 1;
      return;
    }
    _badge.forward();
    _count.forward();
  }

  @override
  void dispose() {
    _badge.dispose();
    _burst.dispose();
    _count.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.completion;
    final keepReading = widget.onKeepReading;
    final spoken = [
      'You finished ${c.title}',
      '${formatCount(c.wordsInBook)} words',
      if (c.chapterCount > 1) '${c.chapterCount} chapters',
    ].join('. ');
    return _MomentScaffold(
      spokenLabel: spoken,
      summary: (context, compact) => [
        _MomentBadge(
          animation: _badge,
          burst: _burst,
          particles: _particles,
          size: compact ? 76 : 112,
          icon: Icons.auto_stories_rounded,
        ),
        SizedBox(height: compact ? 12 : 22),
        const Text(
          'You finished it',
          textAlign: TextAlign.center,
          style: RunThruTypography.momentHeadline,
        ),
        const SizedBox(height: 6),
        Text(
          c.title,
          textAlign: TextAlign.center,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: RunThruTypography.chapterSubtitle,
        ),
        SizedBox(height: compact ? 12 : 24),
        _StatsRow(
          animation: _count,
          stats: [
            (value: c.wordsInBook, text: null, label: 'WORDS'),
            if (c.chapterCount > 1)
              (value: c.chapterCount, text: null, label: 'CHAPTERS'),
            if (c.sessionTime.inSeconds >= 30)
              (value: null, text: _clock(c.sessionTime), label: 'TODAY'),
          ],
        ),
      ],
      actions: (context, compact) => [
        _MomentButton(
          key: BookCompleteOverlay.libraryKey,
          label: 'Back to library',
          semanticLabel: 'Back to library',
          icon: Icons.library_books_rounded,
          onPressed: widget.onLibrary,
        ),
        const SizedBox(height: 4),
        if (keepReading != null)
          _MomentTextButton(
            key: BookCompleteOverlay.keepReadingKey,
            label: c.backMatterMinutes == null
                ? 'Keep reading the notes and extras'
                : 'Keep reading the notes and extras · '
                      '${formatMinutes(c.backMatterMinutes!)}',
            onPressed: keepReading,
          ),
        _MomentTextButton(
          key: BookCompleteOverlay.readAgainKey,
          label: 'Read it again',
          onPressed: widget.onReadAgain,
        ),
      ],
    );
  }
}

/// Shared frame of the chapter-complete and book-complete moments: the
/// summary centred in the space above, the actions at the bottom within
/// thumb reach. Scrolls, and tightens, when the window is short (landscape,
/// split screen, large text).
class _MomentScaffold extends StatelessWidget {
  const _MomentScaffold({
    required this.spokenLabel,
    required this.summary,
    required this.actions,
    this.onBackgroundTouch,
  });

  final String spokenLabel;
  final List<Widget> Function(BuildContext context, bool compact) summary;
  final List<Widget> Function(BuildContext context, bool compact) actions;
  final VoidCallback? onBackgroundTouch;

  @override
  Widget build(BuildContext context) {
    final reduced = isReducedMotion(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: reduced ? Duration.zero : RunThruAnimations.dialEmergeDuration,
      curve: Curves.easeOut,
      builder: (context, t, child) => Opacity(opacity: t, child: child),
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) => onBackgroundTouch?.call(),
        // Swallow taps so they never reach the reader underneath.
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {},
          excludeFromSemantics: true,
          child: ColoredBox(
            color: RunThruTokens.stageMomentWash,
            child: SafeArea(
              top: false,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxHeight < 560;
                  return Semantics(
                    container: true,
                    explicitChildNodes: true,
                    liveRegion: true,
                    label: spokenLabel,
                    // The width limit sits outside IntrinsicHeight: an
                    // intrinsic height asked at the full window width would
                    // assume fewer text lines than the column really has.
                    child: SingleChildScrollView(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: 380 + 48,
                            minHeight: constraints.maxHeight,
                          ),
                          child: IntrinsicHeight(
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(
                                24,
                                compact ? 8 : 16,
                                24,
                                compact ? 10 : 22,
                              ),
                              child: Column(
                                children: [
                                  Expanded(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      mainAxisSize: MainAxisSize.min,
                                      children: summary(context, compact),
                                    ),
                                  ),
                                  SizedBox(height: compact ? 12 : 20),
                                  ...actions(context, compact),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The badge: a raised disc whose ring closes, then a check draws (or an
/// icon lands), then the whole badge pops once.
class _MomentBadge extends StatelessWidget {
  const _MomentBadge({
    required this.animation,
    required this.burst,
    required this.particles,
    required this.size,
    this.icon,
  });

  /// Fraction of the badge animation at which the pop (and the burst and
  /// haptic) happens.
  static const double popAt = 0.7;

  final Animation<double> animation;
  final Animation<double> burst;
  final List<_Particle> particles;
  final double size;

  /// Shown instead of the drawn check (the book-complete badge).
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            // The burst paints far outside the badge.
            Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _BurstPainter(
                    animation: burst,
                    particles: particles,
                    reach: size * 2.6,
                  ),
                ),
              ),
            ),
            AnimatedBuilder(
              animation: animation,
              builder: (context, child) {
                final t = animation.value;
                // One bump past full size as the check lands.
                final bump = t < popAt
                    ? 0.0
                    : math.sin(((t - popAt) / (1 - popAt)) * math.pi);
                return Transform.scale(scale: 1 + 0.14 * bump, child: child);
              },
              child: DecoratedBox(
                decoration: RunThruDecorations.raisedDecoration(
                  RunThruSurface.stage,
                  borderRadius: 999,
                ),
                child: SizedBox(
                  width: size,
                  height: size,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _RingPainter(
                            animation: animation,
                            drawCheck: icon == null,
                          ),
                        ),
                      ),
                      if (icon != null)
                        ScaleTransition(
                          scale: CurvedAnimation(
                            parent: animation,
                            curve: const Interval(
                              0.45,
                              0.8,
                              curve: Curves.easeOutBack,
                            ),
                          ),
                          child: Icon(
                            icon,
                            size: size * 0.42,
                            color: RunThruTokens.shellTealDeep,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.animation, required this.drawCheck})
    : super(repaint: animation);

  final Animation<double> animation;
  final bool drawCheck;

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value.clamp(0.0, 1.0);
    final centre = size.center(Offset.zero);
    final stroke = size.shortestSide * 0.075;
    final radius = size.shortestSide / 2 - stroke * 1.4;

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = RunThruTokens.stageDarkShadow;
    canvas.drawCircle(centre, radius, track);

    final ringT = Curves.easeOutCubic.transform((t / 0.55).clamp(0.0, 1.0));
    if (ringT > 0) {
      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = RunThruTokens.shellTeal;
      canvas.drawArc(
        Rect.fromCircle(center: centre, radius: radius),
        -math.pi / 2,
        math.pi * 2 * ringT,
        false,
        ring,
      );
    }

    if (!drawCheck) return;
    final checkT = Curves.easeOut.transform(((t - 0.42) / 0.3).clamp(0.0, 1.0));
    if (checkT <= 0) return;
    final s = size.shortestSide;
    final path = Path()
      ..moveTo(centre.dx - s * 0.17, centre.dy + s * 0.01)
      ..lineTo(centre.dx - s * 0.05, centre.dy + s * 0.13)
      ..lineTo(centre.dx + s * 0.19, centre.dy - s * 0.12);
    final metric = path.computeMetrics().first;
    final check = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke * 1.15
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = RunThruTokens.shellTealDeep;
    canvas.drawPath(metric.extractPath(0, metric.length * checkT), check);
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      oldDelegate.animation != animation || oldDelegate.drawCheck != drawCheck;
}

/// One piece of the burst.
class _Particle {
  const _Particle({
    required this.angle,
    required this.speed,
    required this.size,
    required this.spin,
    required this.color,
    required this.round,
    required this.delay,
  });

  /// Pieces thrown evenly around a circle with seeded jitter, so every
  /// celebration looks the same and tests are stable.
  static List<_Particle> burst({
    required int count,
    required int seed,
    double delay = 0,
    double reach = 1,
  }) {
    final random = math.Random(seed);
    const colors = RunThruTokens.celebrationColors;
    return [
      for (var i = 0; i < count; i++)
        _Particle(
          angle: (i / count) * math.pi * 2 + (random.nextDouble() - 0.5) * 0.5,
          speed: (0.55 + random.nextDouble() * 0.45) * reach,
          size: 6 + random.nextDouble() * 6,
          spin: (random.nextDouble() - 0.5) * 9,
          color: colors[i % colors.length],
          round: random.nextInt(3) == 0,
          delay: delay + random.nextDouble() * 0.06,
        ),
    ];
  }

  final double angle;

  /// Fraction of the painter's reach this piece travels.
  final double speed;
  final double size;

  /// Turns over the flight (radians).
  final double spin;
  final Color color;

  /// A dot rather than a strip.
  final bool round;

  /// Fraction of the animation before this piece launches.
  final double delay;
}

class _BurstPainter extends CustomPainter {
  _BurstPainter({
    required this.animation,
    required this.particles,
    required this.reach,
  }) : super(repaint: animation);

  final Animation<double> animation;
  final List<_Particle> particles;

  /// How far (logical pixels) the fastest piece travels.
  final double reach;

  @override
  void paint(Canvas canvas, Size size) {
    final progress = animation.value;
    if (progress <= 0 || progress >= 1) return;
    final origin = size.center(Offset.zero);
    final paint = Paint();
    for (final p in particles) {
      final t = ((progress - p.delay) / (1 - p.delay)).clamp(0.0, 1.0);
      if (t <= 0) continue;
      // Fast out, slowing: most of the distance in the first third.
      final travel = 1 - math.pow(1 - t, 3).toDouble();
      final distance = reach * p.speed * travel;
      final fall = reach * 0.42 * t * t; // gravity
      final position =
          origin +
          Offset(math.cos(p.angle), math.sin(p.angle)) * distance +
          Offset(0, fall);
      final fade = t < 0.62 ? 1.0 : (1 - (t - 0.62) / 0.38).clamp(0.0, 1.0);
      paint.color = p.color.withValues(alpha: fade);
      canvas
        ..save()
        ..translate(position.dx, position.dy)
        ..rotate(p.spin * t);
      if (p.round) {
        canvas.drawCircle(Offset.zero, p.size * 0.42, paint);
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset.zero,
              width: p.size * 1.5,
              height: p.size * 0.55,
            ),
            Radius.circular(p.size * 0.2),
          ),
          paint,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_BurstPainter oldDelegate) =>
      oldDelegate.animation != animation || oldDelegate.particles != particles;
}

typedef _Stat = ({int? value, String? text, String label});

/// A row of figures that count up to their values.
class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.animation, required this.stats});

  final Animation<double> animation;
  final List<_Stat> stats;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: DecoratedBox(
        decoration: RunThruDecorations.insetDecoration(
          RunThruSurface.stage,
          size: RunThruShadowSize.small,
          borderRadius: 18,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          child: Row(
            children: [
              for (final stat in stats)
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedBuilder(
                        animation: animation,
                        builder: (context, _) {
                          final eased = Curves.easeOutCubic.transform(
                            animation.value.clamp(0.0, 1.0),
                          );
                          final shown = stat.value == null
                              ? stat.text!
                              : formatCount((stat.value! * eased).round());
                          return FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              shown,
                              maxLines: 1,
                              textScaler: TextScaler.noScaling,
                              style: RunThruTypography.statValue,
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 4),
                      Text(
                        stat.label,
                        textScaler: TextScaler.noScaling,
                        style: RunThruTypography.tinyLabel.copyWith(
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Progress through the book: one segment per chapter (a single bar when
/// there are too many to draw), the newest filling in.
class _BookProgress extends StatelessWidget {
  const _BookProgress({
    required this.animation,
    required this.done,
    required this.total,
    required this.fraction,
  });

  final Animation<double> animation;
  final int done;
  final int total;
  final double fraction;

  static const int _maxSegments = 24;

  @override
  Widget build(BuildContext context) {
    final percent = (fraction * 100).round().clamp(0, 100);
    final caption = '$done of $total chapters  ·  $percent% of the book';
    return ExcludeSemantics(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 8,
            width: double.infinity,
            child: total <= _maxSegments
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < total; i++) ...[
                        if (i > 0) const SizedBox(width: 3),
                        Expanded(
                          child: _Segment(
                            animation: animation,
                            state: i < done - 1
                                ? _SegmentState.done
                                : i == done - 1
                                ? _SegmentState.filling
                                : _SegmentState.ahead,
                          ),
                        ),
                      ],
                    ],
                  )
                : ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: ColoredBox(
                      color: RunThruTokens.stageDarkShadow,
                      child: AnimatedBuilder(
                        animation: animation,
                        builder: (context, _) => FractionallySizedBox(
                          alignment: AlignmentDirectional.centerStart,
                          widthFactor:
                              (fraction *
                                      Curves.easeOutCubic.transform(
                                        animation.value.clamp(0.0, 1.0),
                                      ))
                                  .clamp(0.0, 1.0),
                          child: const ColoredBox(
                            color: RunThruTokens.shellTeal,
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 8),
          Text(
            caption,
            textAlign: TextAlign.center,
            style: RunThruTypography.metadata,
          ),
        ],
      ),
    );
  }
}

enum _SegmentState { done, filling, ahead }

class _Segment extends StatelessWidget {
  const _Segment({required this.animation, required this.state});

  final Animation<double> animation;
  final _SegmentState state;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(999);
    if (state != _SegmentState.filling) {
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          color: state == _SegmentState.done
              ? RunThruTokens.shellTeal
              : RunThruTokens.stageDarkShadow,
        ),
      );
    }
    return ClipRRect(
      borderRadius: radius,
      child: ColoredBox(
        color: RunThruTokens.stageDarkShadow,
        child: AnimatedBuilder(
          animation: animation,
          builder: (context, _) => FractionallySizedBox(
            alignment: AlignmentDirectional.centerStart,
            widthFactor: Curves.easeOutCubic.transform(
              animation.value.clamp(0.0, 1.0),
            ),
            child: const ColoredBox(color: RunThruTokens.shellReady),
          ),
        ),
      ),
    );
  }
}

/// "NEXT · Chapter 4: The Storm · 9 min".
class _NextUp extends StatelessWidget {
  const _NextUp({required this.name, this.minutes});

  final String name;
  final int? minutes;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            minutes == null
                ? 'NEXT'
                : 'NEXT  ·  ${minutes! <= 1 ? '1 MIN' : '$minutes MIN'}',
            textScaler: TextScaler.noScaling,
            style: RunThruTypography.tinyLabel.copyWith(
              letterSpacing: 1.6,
              color: RunThruTokens.shellTealDeep,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: RunThruTypography.rowTitle.copyWith(
              color: RunThruTokens.stageText,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}

/// The primary action. With a running [countdown] its lower edge fills as
/// the action approaches.
class _MomentButton extends StatelessWidget {
  const _MomentButton({
    super.key,
    required this.label,
    required this.semanticLabel,
    required this.icon,
    required this.onPressed,
    this.countdown,
  });

  final String label;
  final String semanticLabel;
  final IconData icon;
  final VoidCallback onPressed;
  final Animation<double>? countdown;

  @override
  Widget build(BuildContext context) {
    final countdown = this.countdown;
    return Semantics(
      button: true,
      label: semanticLabel,
      onTap: onPressed,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: () {
          HapticFeedback.lightImpact();
          onPressed();
        },
        child: ExcludeSemantics(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: DecoratedBox(
              decoration: RunThruDecorations.tealButton(borderRadius: 18),
              child: SizedBox(
                height: 56,
                width: double.infinity,
                child: Stack(
                  children: [
                    if (countdown != null)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        height: 4,
                        child: AnimatedBuilder(
                          animation: countdown,
                          builder: (context, _) => FractionallySizedBox(
                            alignment: AlignmentDirectional.centerStart,
                            widthFactor: countdown.value.clamp(0.0, 1.0),
                            child: ColoredBox(
                              color: RunThruTokens.shellCream.withValues(
                                alpha: 0.75,
                              ),
                            ),
                          ),
                        ),
                      ),
                    Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(label, style: RunThruTypography.primaryButton),
                          const SizedBox(width: 8),
                          Icon(icon, size: 20, color: RunThruTokens.shellCream),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A quiet secondary action, still a full 48dp target.
class _MomentTextButton extends StatelessWidget {
  const _MomentTextButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      onTap: onPressed,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: onPressed,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: RunThruA11y.minTapTarget,
            minWidth: 160,
          ),
          child: Center(
            child: ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: RunThruTypography.rowTitle.copyWith(
                    color: RunThruTokens.shellTealDeep,
                    fontWeight: FontWeight.w600,
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
