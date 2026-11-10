import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runthru/core/orp.dart';
import 'package:runthru/core/reading_goal_presets.dart';
import 'package:runthru/design/design.dart';
import 'package:runthru/store/config.dart';
import 'package:runthru/store/models.dart';
import 'package:runthru/widgets/runthru_shell_widgets.dart';

/// Shared live target for the Library Continue Reading tour spotlight.
final GlobalKey libraryContinueTourTargetKey = GlobalKey(
  debugLabel: 'library-continue-tour-target',
);

/// Blocks reading entry until first-run reading goal onboarding is resolved.
///
/// The child is not built while onboarding is pending, so reader widgets cannot
/// start playback before the persisted gate has been checked. App-shell
/// onboarding can opt in to mounting its child so the Library tour has a live
/// Continue Reading card target.
class ReadingEntryOnboardingGate extends ConsumerWidget {
  const ReadingEntryOnboardingGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(configProvider);
    final resolved = config.valueOrNull;

    if (resolved == null) {
      return const ColoredBox(color: RunThruTokens.stageBase);
    }

    if (resolved.hasSeenReadingGoalOnboarding) {
      return child;
    }

    return ReadingGoalOnboardingOverlay(
      onSelected: (goal) async {
        final notifier = ref.read(configProvider.notifier);
        await notifier.applyReadingGoalPreset(goal);
        await notifier.setHasSeenReadingGoalOnboarding(true);
      },
    );
  }
}

class ReadingGoalOnboardingOverlay extends StatefulWidget {
  const ReadingGoalOnboardingOverlay({super.key, required this.onSelected});

  final FutureOr<void> Function(ReadingGoalConfig goal) onSelected;

  @override
  State<ReadingGoalOnboardingOverlay> createState() =>
      _ReadingGoalOnboardingOverlayState();
}

class _ReadingGoalOnboardingOverlayState
    extends State<ReadingGoalOnboardingOverlay> {
  final PageController _introController = PageController();
  late _OnboardingPhase _phase;
  var _introIndex = 0;
  late int _tourIndex;
  var _completing = false;

  ReadingGoalConfig get _comfortableGoal => readingGoalConfigs.firstWhere(
    (c) => c.preset == ReadingGoalPreset.comfortable,
  );

  @override
  void initState() {
    super.initState();
    _phase = _OnboardingPhase.intro;
    _tourIndex = 0;
  }

  @override
  void dispose() {
    _introController.dispose();
    super.dispose();
  }

  Future<void> _complete() async {
    if (_completing) return;
    setState(() => _completing = true);
    await Future<void>.sync(() => widget.onSelected(_comfortableGoal));
  }

  void _nextIntro() {
    final last = _introIndex == _introCards.length - 1;
    if (last) {
      setState(() => _phase = _OnboardingPhase.tour);
      return;
    }
    // Reduced motion must jump: nextPage(duration: Duration.zero) completes
    // inside DrivenScrollActivity's constructor and throws
    // LateInitializationError, leaving the user stuck on the first card.
    if (isReducedMotion(context)) {
      _introController.jumpToPage(_introIndex + 1);
      return;
    }
    _introController.nextPage(
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
    );
  }

  void _nextTour() {
    final last = _tourIndex == _tourSteps.length - 1;
    if (last) {
      unawaited(_complete());
      return;
    }
    setState(() => _tourIndex += 1);
  }

  @override
  Widget build(BuildContext context) {
    final reducedMotion = isReducedMotion(context);

    if (_phase == _OnboardingPhase.tour) {
      return Material(
        type: MaterialType.transparency,
        textStyle: const TextStyle(decoration: TextDecoration.none),
        child: MockedReaderTour(
          key: const ValueKey('tour'),
          stepIndex: _tourIndex,
          completing: _completing,
          onSkip: _complete,
          onNext: _nextTour,
        ),
      );
    }

    return _IntroShellFrame(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final horizontal = width < 360 ? 14.0 : 22.0;
        final compact = height < 640 || width < 360;

        return AnimatedSwitcher(
          duration: reducedMotion
              ? Duration.zero
              : const Duration(milliseconds: 260),
          child: _IntroCarousel(
            key: const ValueKey('intro'),
            controller: _introController,
            currentIndex: _introIndex,
            compact: compact,
            completing: _completing,
            horizontalPadding: horizontal,
            onPageChanged: (value) {
              setState(() => _introIndex = value);
            },
            onSkip: _complete,
            onNext: _nextIntro,
          ),
        );
      },
    );
  }
}

enum _OnboardingPhase { intro, tour }

class _IntroShellFrame extends StatelessWidget {
  const _IntroShellFrame({required this.builder});

  final Widget Function(BuildContext context, BoxConstraints constraints)
  builder;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: RunThruTokens.shellSandDeep,
      textStyle: const TextStyle(decoration: TextDecoration.none),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.32),
            radius: 1.22,
            colors: [
              RunThruTokens.shellCream,
              RunThruTokens.shellSandHi,
              RunThruTokens.shellSandDeep,
            ],
            stops: [0, 0.56, 1],
          ),
        ),
        child: SafeArea(
          minimum: const EdgeInsets.fromLTRB(0, 8, 0, 10),
          child: LayoutBuilder(builder: builder),
        ),
      ),
    );
  }
}

class _IntroCardData {
  const _IntroCardData({
    required this.eyebrow,
    required this.title,
    required this.body,
    required this.accent,
    required this.art,
  });

  final String eyebrow;
  final String title;
  final String body;
  final Color accent;
  final _IntroArt art;
}

enum _IntroArt { mark, saccade, pace }

const _introCards = [
  _IntroCardData(
    eyebrow: 'Welcome to RunThru',
    title: 'Reading, brought to you.',
    body:
        'Instead of dragging your eyes across the page, RunThru shows you one word at a time, right where you are already looking.',
    accent: RunThruTokens.shellTeal,
    art: _IntroArt.mark,
  ),
  _IntroCardData(
    eyebrow: 'Why it feels easier',
    title: 'Your eyes get to rest.',
    body:
        'Normally your eyes hop four or five times across every line. Hold them in one spot and there is simply less work to do.',
    accent: Color(0xFFC48B2E),
    art: _IntroArt.saccade,
  ),
  _IntroCardData(
    eyebrow: 'On your terms',
    title: 'It was never a race.',
    body:
        'Start gentle. Nudge the speed up only when it feels easy. RunThru bends to you, never the other way around.',
    accent: Color(0xFFBF4733),
    art: _IntroArt.pace,
  ),
];

class _TourStep {
  const _TourStep({
    required this.eyebrow,
    required this.title,
    required this.body,
    required this.cta,
    required this.icon,
    required this.accent,
    required this.word,
    required this.wpm,
    required this.progress,
    required this.target,
    required this.playing,
    required this.showFocusHint,
  });

  final String eyebrow;
  final String title;
  final String body;
  final String cta;
  final IconData icon;
  final Color accent;
  final String word;
  final int wpm;
  final double progress;
  final _MockTourTarget target;
  final bool playing;
  final bool showFocusHint;
}

enum _MockTourTarget { word, tintedLetter, focus, prev, next, speed, play }

const _tourSteps = [
  _TourStep(
    eyebrow: 'One word at a time',
    title: 'No place to lose.',
    body:
        'Each word arrives in the same spot. Nothing to scan, nothing to track, so you never lose your line.',
    cta: 'Got it',
    icon: Icons.center_focus_strong_outlined,
    accent: Color(0xFFC48B2E),
    word: 'steady',
    wpm: 260,
    progress: 0.18,
    target: _MockTourTarget.word,
    playing: true,
    showFocusHint: false,
  ),
  _TourStep(
    eyebrow: 'The tinted letter',
    title: 'A spot to lock onto.',
    body:
        'That tinted letter sits where your brain recognizes a word fastest. Every word lines up to it.',
    cta: 'Nice',
    icon: Icons.adjust_rounded,
    accent: Color(0xFFBF4733),
    word: 'reading',
    wpm: 280,
    progress: 0.31,
    target: _MockTourTarget.tintedLetter,
    playing: true,
    showFocusHint: false,
  ),
  _TourStep(
    eyebrow: 'Focus mode',
    title: 'Only what matters.',
    body:
        'When you pause, focus mode can show the sentence around the word without leaving the reader.',
    cta: 'Okay',
    icon: Icons.visibility_outlined,
    accent: Color(0xFF6E5C9A),
    word: 'anchor',
    wpm: 280,
    progress: 0.44,
    target: _MockTourTarget.focus,
    playing: false,
    showFocusHint: true,
  ),
  _TourStep(
    eyebrow: 'Slipped past you?',
    title: 'Step back a sentence.',
    body:
        'Tap back to jump to the start of the sentence and let it replay. Re-read as often as you like.',
    cta: 'Handy',
    icon: Icons.keyboard_double_arrow_left_rounded,
    accent: Color(0xFFAD4D6B),
    word: 'sentence',
    wpm: 260,
    progress: 0.57,
    target: _MockTourTarget.prev,
    playing: false,
    showFocusHint: false,
  ),
  _TourStep(
    eyebrow: 'Ready to move on?',
    title: 'Step forward a sentence.',
    body:
        'When you have the idea, jump forward and keep your momentum without scrubbing through words.',
    cta: 'Got it',
    icon: Icons.keyboard_double_arrow_right_rounded,
    accent: Color(0xFF3E7D70),
    word: 'momentum',
    wpm: 300,
    progress: 0.70,
    target: _MockTourTarget.next,
    playing: false,
    showFocusHint: false,
  ),
  _TourStep(
    eyebrow: 'Your pace, your call',
    title: 'Dial it in.',
    body:
        'Start gentle and climb only when it feels easy. You are always in charge of the speed.',
    cta: 'Start reading',
    icon: Icons.speed_rounded,
    accent: RunThruTokens.shellTeal,
    word: 'comfortable',
    wpm: 320,
    progress: 0.84,
    target: _MockTourTarget.speed,
    playing: true,
    showFocusHint: false,
  ),
];

class _IntroCarousel extends StatelessWidget {
  const _IntroCarousel({
    super.key,
    required this.controller,
    required this.currentIndex,
    required this.compact,
    required this.completing,
    required this.horizontalPadding,
    required this.onPageChanged,
    required this.onSkip,
    required this.onNext,
  });

  final PageController controller;
  final int currentIndex;
  final bool compact;
  final bool completing;
  final double horizontalPadding;
  final ValueChanged<int> onPageChanged;
  final VoidCallback onSkip;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final current = _introCards[currentIndex];
    final last = currentIndex == _introCards.length - 1;
    return Column(
      children: [
        SizedBox(
          height: 48,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Text(
                'RUNTHRU · FIRST LAUNCH',
                textScaler: TextScaler.noScaling,
                style: RunThruTypography.tinyLabel.copyWith(
                  color: RunThruTokens.shellInkFaint.withValues(alpha: 0.65),
                  letterSpacing: 1.6,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: _QuietTextButton(
                  label: 'Skip',
                  onPressed: completing ? null : onSkip,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: PageView.builder(
            controller: controller,
            onPageChanged: onPageChanged,
            itemCount: _introCards.length,
            itemBuilder: (context, index) => Padding(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                compact ? 2 : 14,
                horizontalPadding,
                8,
              ),
              child: _IntroPage(card: _introCards[index], compact: compact),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            6,
            horizontalPadding,
            22,
          ),
          child: Column(
            children: [
              _StepDots(
                count: _introCards.length,
                index: currentIndex,
                accent: current.accent,
              ),
              const SizedBox(height: 18),
              _PrimaryOnboardingButton(
                label: last ? 'Show me how' : 'Next',
                accent: current.accent,
                onPressed: completing ? null : onNext,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _IntroPage extends StatelessWidget {
  const _IntroPage({required this.card, required this.compact});

  final _IntroCardData card;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final copyVariant = card.art == _IntroArt.mark
        ? _IntroCopyVariant.welcome
        : _IntroCopyVariant.standard;
    if (compact || textScale > 1.25) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: compact ? 184 : 220,
                  child: Center(
                    child: _IntroArtView(
                      art: card.art,
                      accent: card.accent,
                      compact: true,
                    ),
                  ),
                ),
                _IntroCopy(card: card, compact: true, variant: copyVariant),
              ],
            ),
          ),
        ),
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: _IntroArtView(
                  art: card.art,
                  accent: card.accent,
                  compact: compact,
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.only(bottom: compact ? 4 : 18),
              child: _IntroCopy(
                card: card,
                compact: compact,
                variant: copyVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _IntroCopyVariant { standard, welcome }

class _IntroCopy extends StatelessWidget {
  const _IntroCopy({
    required this.card,
    required this.compact,
    this.variant = _IntroCopyVariant.standard,
  });

  final _IntroCardData card;
  final bool compact;
  final _IntroCopyVariant variant;

  @override
  Widget build(BuildContext context) {
    final welcome = variant == _IntroCopyVariant.welcome;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          card.eyebrow.toUpperCase(),
          style: RunThruTypography.tinyLabel.copyWith(
            color: welcome ? RunThruTokens.shellTealDeep : card.accent,
            fontSize: welcome ? 11 : null,
            fontWeight: welcome ? FontWeight.w700 : FontWeight.w800,
            letterSpacing: welcome ? 1.5 : null,
          ),
        ),
        SizedBox(height: compact ? 8 : 12),
        Text(
          card.title,
          style: RunThruTypography.display.copyWith(
            color: RunThruTokens.shellInk,
            fontSize: welcome ? 24 : null,
            fontWeight: FontWeight.w800,
            height: welcome ? 1.1 : 1.08,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          card.body,
          style: RunThruTypography.body.copyWith(
            color: RunThruTokens.shellInkSoft,
            fontSize: welcome ? 15 : null,
            fontWeight: welcome ? FontWeight.w400 : null,
            height: 1.48,
          ),
        ),
      ],
    );
  }
}

class _IntroArtView extends StatelessWidget {
  const _IntroArtView({
    required this.art,
    required this.accent,
    required this.compact,
  });

  final _IntroArt art;
  final Color accent;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return switch (art) {
      _IntroArt.mark => _MarkArt(accent: accent, compact: compact),
      _IntroArt.saccade => _SaccadeArt(accent: accent, compact: compact),
      _IntroArt.pace => _PaceArt(accent: accent, compact: compact),
    };
  }
}

class _MarkArt extends StatelessWidget {
  const _MarkArt({required this.accent, required this.compact});

  final Color accent;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final markSize = compact ? 70.0 : 108.0;
    final haloSize = markSize * (compact ? 1.9 : 2.05);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: haloSize,
          height: haloSize,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(
                    sigmaX: compact ? 7 : 9,
                    sigmaY: compact ? 7 : 9,
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          accent.withValues(alpha: 0.34),
                          accent.withValues(alpha: 0.18),
                          RunThruTokens.shellTealDeep.withValues(alpha: 0.07),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.38, 0.58, 1.0],
                      ),
                    ),
                  ),
                ),
              ),
              Container(
                width: markSize * 1.42,
                height: markSize * 1.42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      RunThruTokens.shellCream.withValues(alpha: 0.48),
                      accent.withValues(alpha: 0.16),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.54, 1.0],
                  ),
                ),
              ),
              Container(
                width: markSize * 1.04,
                height: markSize * 1.04,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withValues(alpha: 0.09),
                ),
              ),
              RunThruMark(size: markSize, semanticLabel: 'RunThru'),
            ],
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                RunThruTokens.shellSandHi.withValues(alpha: 0.74),
                RunThruTokens.shellSand.withValues(alpha: 0.58),
              ],
            ),
            border: Border.all(
              color: RunThruTokens.shellSandHi.withValues(alpha: 0.78),
              width: 0.6,
            ),
            boxShadow: [
              BoxShadow(
                color: RunThruTokens.shellCream.withValues(alpha: 0.62),
                offset: const Offset(-3, -3),
                blurRadius: 8,
              ),
              BoxShadow(
                color: RunThruTokens.shellSandDeep.withValues(alpha: 0.58),
                offset: const Offset(4, 5),
                blurRadius: 10,
              ),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 16 : 22,
              compact ? 7 : 9,
              compact ? 16 : 22,
              compact ? 8 : 10,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'RunThru',
                  textScaler: TextScaler.noScaling,
                  style: RunThruTypography.display.copyWith(
                    fontSize: compact ? 23 : 30,
                    fontWeight: FontWeight.w800,
                    color: RunThruTokens.shellInk,
                    height: 0.96,
                  ),
                ),
                SizedBox(height: compact ? 4 : 5),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: SizedBox(
                    width: compact ? 56 : 74,
                    height: compact ? 2 : 2.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SaccadeArt extends StatelessWidget {
  const _SaccadeArt({required this.accent, required this.compact});

  final Color accent;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final padding = compact ? 14.0 : 18.0;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 280,
        maxHeight: compact ? 178 : 224,
      ),
      child: Container(
        padding: EdgeInsets.all(padding),
        decoration: RunThruDecorations.designerInset(borderRadius: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'USUALLY · EYES HOP',
              textScaler: TextScaler.noScaling,
              style: RunThruTypography.tinyLabel.copyWith(
                color: RunThruTokens.shellInkFaint.withValues(alpha: 0.72),
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.15,
              ),
            ),
            SizedBox(height: compact ? 8 : 12),
            SizedBox(
              key: const ValueKey('intro-eye-hop-path'),
              height: compact ? 48 : 56,
              child: const Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(painter: _EyeHopPathPainter()),
                  ),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _WordChip(text: 'the', muted: true),
                          SizedBox(width: 9),
                          _WordChip(text: 'line', muted: true),
                          SizedBox(width: 9),
                          _WordChip(text: 'keeps', muted: true),
                          SizedBox(width: 9),
                          _WordChip(text: 'moving', muted: true),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: compact ? 10 : 18),
            DecoratedBox(
              decoration: BoxDecoration(
                color: RunThruTokens.shellDivider.withValues(alpha: 0.42),
              ),
              child: const SizedBox(height: 1, width: double.infinity),
            ),
            SizedBox(height: compact ? 6 : 10),
            Text(
              'RUNTHRU · EYES STILL',
              textScaler: TextScaler.noScaling,
              style: RunThruTypography.tinyLabel.copyWith(
                color: accent,
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.15,
              ),
            ),
            SizedBox(height: compact ? 8 : 12),
            Center(
              child: _WordChip(text: 'reading', accent: accent),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaceArt extends StatelessWidget {
  const _PaceArt({required this.accent, required this.compact});

  final Color accent;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    const fillFraction = 0.38;
    const thumbSize = 26.0;
    const trackHeight = 14.0;

    return SizedBox(
      width: 276,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: RunThruDecorations.designerRaisedSmall(
              borderRadius: 16,
            ),
            child: RichText(
              textScaler: TextScaler.noScaling,
              text: TextSpan(
                style: RunThruTypography.display.copyWith(
                  color: RunThruTokens.shellInk,
                  fontWeight: FontWeight.w800,
                  fontSize: 30,
                ),
                children: const [
                  TextSpan(text: '300 '),
                  TextSpan(text: 'WPM', style: TextStyle(fontSize: 13)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final trackWidth = constraints.maxWidth;
              final thumbLeft = (trackWidth * fillFraction - thumbSize / 2)
                  .clamp(0.0, trackWidth - thumbSize);

              return SizedBox(
                height: thumbSize,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.centerLeft,
                  children: [
                    Container(
                      height: trackHeight,
                      decoration: RunThruDecorations.designerInset(
                        borderRadius: 999,
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: fillFraction,
                          child: Container(
                            decoration: BoxDecoration(
                              color: accent,
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: thumbLeft,
                      top: 0,
                      child: Container(
                        width: thumbSize,
                        height: thumbSize,
                        decoration: RunThruDecorations.designerRaisedSmall(
                          borderRadius: thumbSize / 2,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 10),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Easy',
                textScaler: TextScaler.noScaling,
                style: RunThruTypography.tinyLabel,
              ),
              Text(
                'Faster',
                textScaler: TextScaler.noScaling,
                style: RunThruTypography.tinyLabel,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class MockedReaderTour extends StatefulWidget {
  const MockedReaderTour({
    super.key,
    required this.stepIndex,
    required this.completing,
    required this.onSkip,
    required this.onNext,
  });

  final int stepIndex;
  final bool completing;
  final VoidCallback onSkip;
  final VoidCallback onNext;

  @override
  State<MockedReaderTour> createState() => _MockedReaderTourState();
}

class _MockedReaderTourState extends State<MockedReaderTour> {
  final Map<_MockTourTarget, GlobalKey> _targetKeys = {
    for (final target in _MockTourTarget.values) target: GlobalKey(),
  };
  final GlobalKey _stageStackKey = GlobalKey();
  Rect? _holeRect;

  @override
  Widget build(BuildContext context) {
    final step = _tourSteps[widget.stepIndex];
    final reduced = isReducedMotion(context);

    // Re-measure after this frame — covers step changes, first layout, and
    // any late settle of the FittedBox scale (converges via rect equality).
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureHole());

    return ColoredBox(
      color: RunThruTokens.stageBase,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact =
              constraints.maxHeight < 680 || constraints.maxWidth < 370;
          final cardMaxWidth = math.min(420.0, constraints.maxWidth - 32);

          return Stack(
            key: _stageStackKey,
            children: [
              Positioned.fill(
                child: SafeArea(
                  minimum: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                  child: AbsorbPointer(
                    child: _MockReaderSurface(
                      step: step,
                      compact: compact,
                      targetKeys: _targetKeys,
                    ),
                  ),
                ),
              ),
              // Spotlight scrim: dims the full screen edge-to-edge except a
              // hole punched around the live target (design ob-tour.jsx).
              if (_holeRect != null)
                Positioned.fill(
                  child: IgnorePointer(
                    child: ExcludeSemantics(
                      child: KeyedSubtree(
                        key: ValueKey(
                          'mock-tour-highlight-${step.target.name}',
                        ),
                        child: TweenAnimationBuilder<Rect?>(
                          tween: RectTween(begin: _holeRect, end: _holeRect),
                          duration: reduced
                              ? Duration.zero
                              : const Duration(milliseconds: 420),
                          curve: Curves.easeOutCubic,
                          builder: (context, hole, _) {
                            return CustomPaint(
                              size: Size.infinite,
                              painter: _SpotlightScrimPainter(
                                hole: hole ?? _holeRect!,
                                accent: step.accent,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              Positioned.fill(
                child: SafeArea(
                  minimum: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.only(top: 12),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: cardMaxWidth),
                        child: _CoachCard(
                          key: const ValueKey('mock-tour-card'),
                          step: step,
                          stepIndex: widget.stepIndex,
                          total: _tourSteps.length,
                          completing: widget.completing,
                          pointerAbove: false,
                          ctaKey: const ValueKey('mock-tour-cta'),
                          skipKey: const ValueKey('mock-tour-skip'),
                          onSkip: widget.onSkip,
                          onNext: widget.onNext,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Measures the active target's rect in stage-stack coordinates (through
  /// the FittedBox scale) and updates the spotlight hole.
  void _measureHole() {
    if (!mounted) return;
    final step = _tourSteps[widget.stepIndex];
    // The tinted letter spotlights a small zone at the word card's centre.
    final anchorTarget = step.target == _MockTourTarget.tintedLetter
        ? _MockTourTarget.word
        : step.target;
    final stackBox =
        _stageStackKey.currentContext?.findRenderObject() as RenderBox?;
    final targetBox =
        _targetKeys[anchorTarget]?.currentContext?.findRenderObject()
            as RenderBox?;
    if (stackBox == null || targetBox == null || !targetBox.attached) return;

    var rect = MatrixUtils.transformRect(
      targetBox.getTransformTo(stackBox),
      Offset.zero & targetBox.size,
    );
    if (step.target == _MockTourTarget.tintedLetter) {
      rect = Rect.fromCenter(center: rect.center, width: 58, height: 78);
    }
    if (_holeRect != rect) {
      setState(() => _holeRect = rect);
    }
  }
}

/// Fills the stage with the warm tour scrim, leaving a rounded spotlight
/// hole over the target with an accent ring and soft glow.
class _SpotlightScrimPainter extends CustomPainter {
  const _SpotlightScrimPainter({required this.hole, required this.accent});

  final Rect hole;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final padded = hole.inflate(9);
    final radius = math.min(18.0, padded.height / 2);
    final holeRRect = RRect.fromRectAndRadius(padded, Radius.circular(radius));

    final scrimPath = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()..addRRect(holeRRect),
    );
    canvas.drawPath(
      scrimPath,
      Paint()..color = RunThruTokens.tourScrim.withValues(alpha: 0.62),
    );

    // Soft accent glow around the hole.
    canvas.drawRRect(
      holeRRect,
      Paint()
        ..color = accent.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 13),
    );
    // Crisp accent ring.
    canvas.drawRRect(
      holeRRect,
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(_SpotlightScrimPainter old) =>
      old.hole != hole || old.accent != accent;
}

class _MockReaderSurface extends StatelessWidget {
  const _MockReaderSurface({
    required this.step,
    required this.compact,
    required this.targetKeys,
  });

  final _TourStep step;
  final bool compact;
  final Map<_MockTourTarget, GlobalKey> targetKeys;

  @override
  Widget build(BuildContext context) {
    final topGap = compact ? 8.0 : 16.0;
    final wordHeight = compact ? 128.0 : 164.0;
    final controlGap = compact ? 16.0 : 22.0;

    return ExcludeSemantics(
      child: Container(
        key: const ValueKey('mock-tour-surface'),
        padding: EdgeInsets.fromLTRB(2, topGap, 2, compact ? 198 : 238),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: constraints.maxWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _MockReaderChrome(step: step),
                    const SizedBox(height: 13),
                    _MockProgressBar(
                      progress: step.progress,
                      accent: step.accent,
                    ),
                    SizedBox(height: compact ? 18 : 26),
                    SizedBox(
                      height: wordHeight,
                      child: Center(
                        child: KeyedSubtree(
                          key: targetKeys[_MockTourTarget.word],
                          child: _MockWordCard(step: step, compact: compact),
                        ),
                      ),
                    ),
                    if (step.showFocusHint) ...[
                      const SizedBox(height: 10),
                      KeyedSubtree(
                        key: targetKeys[_MockTourTarget.focus],
                        child: _MockFocusHint(step: step, compact: compact),
                      ),
                    ],
                    SizedBox(height: controlGap),
                    _MockPlaybackControls(
                      step: step,
                      compact: compact,
                      targetKeys: targetKeys,
                    ),
                    SizedBox(height: compact ? 14 : 18),
                    KeyedSubtree(
                      key: targetKeys[_MockTourTarget.speed],
                      child: _MockSpeedSelector(step: step, compact: compact),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _MockReaderChrome extends StatelessWidget {
  const _MockReaderChrome({required this.step});

  final _TourStep step;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _MockChromeButton(icon: Icons.keyboard_arrow_down_rounded, step: step),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Sample reader',
                textScaler: TextScaler.noScaling,
                style: RunThruTypography.caption.copyWith(
                  color: RunThruTokens.stageText,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${(step.progress * 100).round()}% complete',
                textScaler: TextScaler.noScaling,
                style: RunThruTypography.tinyLabel.copyWith(
                  color: RunThruTokens.stageText.withValues(alpha: 0.54),
                ),
              ),
            ],
          ),
        ),
        _MockChromeButton(icon: Icons.more_horiz_rounded, step: step),
      ],
    );
  }
}

class _MockChromeButton extends StatelessWidget {
  const _MockChromeButton({required this.icon, required this.step});

  final IconData icon;
  final _TourStep step;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: RunThruDecorations.raisedDecoration(
        RunThruSurface.stage,
        size: RunThruShadowSize.small,
        borderRadius: 999,
      ),
      child: Icon(icon, color: RunThruTokens.stageText, size: 22),
    );
  }
}

class _MockProgressBar extends StatelessWidget {
  const _MockProgressBar({required this.progress, required this.accent});

  final double progress;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 5,
      child: DecoratedBox(
        decoration: RunThruDecorations.insetDecoration(
          RunThruSurface.stage,
          size: RunThruShadowSize.small,
          borderRadius: 999,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: progress,
              child: ColoredBox(color: accent),
            ),
          ),
        ),
      ),
    );
  }
}

class _MockWordCard extends StatelessWidget {
  const _MockWordCard({required this.step, required this.compact});

  final _TourStep step;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final word = step.word;
    final pivot = bucketedOrpIndex(word).clamp(0, word.length - 1).toInt();
    final style = RunThruTypography.display.copyWith(
      color: RunThruTokens.stageText,
      fontSize: compact ? 34 : 42,
      fontWeight: FontWeight.w800,
      letterSpacing: 0,
    );
    final direction = Directionality.of(context);
    // Shift the word so the anchor letter sits at the card's centre —
    // the same ORP pinning the real reader uses.
    final prefixWidth = _textWidth(word.substring(0, pivot), style, direction);
    final letterWidth = _textWidth(
      word.substring(pivot, pivot + 1),
      style,
      direction,
    );
    final wordWidth = _textWidth(word, style, direction);
    final shift = wordWidth / 2 - (prefixWidth + letterWidth / 2);

    return Container(
      key: const ValueKey('mock-tour-word-card'),
      width: compact ? 266 : 320,
      height: compact ? 104 : 126,
      decoration: BoxDecoration(
        color: RunThruTokens.stageBase,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: RunThruTokens.stageLightShadow,
            offset: Offset(-6, -6),
            blurRadius: 14,
          ),
          BoxShadow(
            color: RunThruTokens.stageDarkShadow,
            offset: Offset(7, 8),
            blurRadius: 18,
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Transform.translate(
        offset: Offset(shift, 0),
        child: RichText(
          textScaler: TextScaler.noScaling,
          text: TextSpan(
            style: style,
            children: [
              TextSpan(text: word.substring(0, pivot)),
              TextSpan(
                text: word.substring(pivot, pivot + 1),
                style: TextStyle(color: step.accent),
              ),
              TextSpan(text: word.substring(pivot + 1)),
            ],
          ),
        ),
      ),
    );
  }

  double _textWidth(String text, TextStyle style, TextDirection direction) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: direction,
      maxLines: 1,
    )..layout();
    return painter.width;
  }
}

class _MockFocusHint extends StatelessWidget {
  const _MockFocusHint({required this.step, required this.compact});

  final _TourStep step;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('mock-tour-focus-hint'),
      width: compact ? 286 : 340,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: RunThruTokens.stageBase,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: step.accent.withValues(alpha: 0.42)),
        boxShadow: const [
          BoxShadow(
            color: RunThruTokens.stageDarkShadow,
            offset: Offset(3, 4),
            blurRadius: 10,
          ),
        ],
      ),
      child: Text(
        '...the sentence stays close while anchor remains centered...',
        textScaler: TextScaler.noScaling,
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.fade,
        softWrap: false,
        style: RunThruTypography.caption.copyWith(
          color: RunThruTokens.stageText.withValues(alpha: 0.78),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _MockPlaybackControls extends StatelessWidget {
  const _MockPlaybackControls({
    required this.step,
    required this.compact,
    required this.targetKeys,
  });

  final _TourStep step;
  final bool compact;
  final Map<_MockTourTarget, GlobalKey> targetKeys;

  @override
  Widget build(BuildContext context) {
    final buttonSize = compact ? 46.0 : 52.0;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        KeyedSubtree(
          key: targetKeys[_MockTourTarget.prev],
          child: _MockControlButton(
            key: const ValueKey('mock-tour-prev'),
            size: buttonSize,
            icon: Icons.keyboard_double_arrow_left_rounded,
          ),
        ),
        SizedBox(width: compact ? 15 : 20),
        KeyedSubtree(
          key: targetKeys[_MockTourTarget.play],
          child: _MockControlButton(
            key: const ValueKey('mock-tour-play'),
            size: buttonSize + 12,
            icon: step.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            accent: step.accent,
          ),
        ),
        SizedBox(width: compact ? 15 : 20),
        KeyedSubtree(
          key: targetKeys[_MockTourTarget.next],
          child: _MockControlButton(
            key: const ValueKey('mock-tour-next'),
            size: buttonSize,
            icon: Icons.keyboard_double_arrow_right_rounded,
          ),
        ),
      ],
    );
  }
}

class _MockControlButton extends StatelessWidget {
  const _MockControlButton({
    super.key,
    required this.icon,
    this.size = 52,
    this.accent,
  });

  final IconData icon;
  final double size;

  /// Accent fill for the primary (play/pause) button; null = raised stage.
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final primary = accent != null;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: primary ? accent : RunThruTokens.stageBase,
        shape: BoxShape.circle,
        boxShadow: [
          const BoxShadow(
            color: RunThruTokens.stageLightShadow,
            offset: Offset(-3, -3),
            blurRadius: 7,
          ),
          BoxShadow(
            color: primary
                ? accent!.withValues(alpha: 0.45)
                : RunThruTokens.stageDarkShadow,
            offset: const Offset(3, 4),
            blurRadius: 9,
          ),
        ],
      ),
      child: Icon(
        icon,
        color: primary ? RunThruTokens.shellCream : RunThruTokens.stageText,
        size: primary ? 30 : 24,
      ),
    );
  }
}

class _MockSpeedSelector extends StatelessWidget {
  const _MockSpeedSelector({required this.step, required this.compact});

  final _TourStep step;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final speeds = [step.wpm - 40, step.wpm, step.wpm + 40];
    return Container(
      key: const ValueKey('mock-tour-speed-selector'),
      width: compact ? 282 : 324,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: RunThruTokens.stageBase,
        borderRadius: BorderRadius.circular(999),
        boxShadow: const [
          BoxShadow(
            color: RunThruTokens.stageLightShadow,
            offset: Offset(-2, -2),
            blurRadius: 5,
          ),
          BoxShadow(
            color: RunThruTokens.stageDarkShadow,
            offset: Offset(2, 2),
            blurRadius: 6,
          ),
        ],
      ),
      child: Row(
        children: [
          for (final speed in speeds)
            Expanded(
              child: Container(
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: speed == step.wpm ? step.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$speed WPM',
                  textScaler: TextScaler.noScaling,
                  style: RunThruTypography.tinyLabel.copyWith(
                    color: speed == step.wpm
                        ? RunThruTokens.shellCream
                        : RunThruTokens.stageText.withValues(alpha: 0.62),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CoachCard extends StatelessWidget {
  const _CoachCard({
    super.key,
    required this.step,
    required this.stepIndex,
    required this.total,
    required this.completing,
    required this.pointerAbove,
    this.ctaKey,
    this.skipKey,
    required this.onSkip,
    required this.onNext,
  });

  final _TourStep step;
  final int stepIndex;
  final int total;
  final bool completing;
  final bool pointerAbove;
  final Key? ctaKey;
  final Key? skipKey;
  final VoidCallback onSkip;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final compact =
        MediaQuery.sizeOf(context).height < 640 ||
        MediaQuery.sizeOf(context).width < 360;
    final stackFooter = compact || textScale > 1.25;

    return Semantics(
      liveRegion: true,
      label: '${step.eyebrow}. ${step.title} ${step.body}',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Align(
            alignment: pointerAbove
                ? Alignment.topCenter
                : Alignment.bottomCenter,
            child: _CoachCardPointer(pointerAbove: pointerAbove),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(17, 17, 17, 15),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFECE3CF), Color(0xFFDDD4BF)],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: RunThruTokens.shellCream.withValues(alpha: 0.64),
                  offset: const Offset(-7, -7),
                  blurRadius: 16,
                ),
                BoxShadow(
                  color: const Color(0xFF3C301C).withValues(alpha: 0.30),
                  offset: const Offset(8, 9),
                  blurRadius: 22,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: step.accent.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: step.accent.withValues(alpha: 0.30),
                          width: 1.2,
                        ),
                      ),
                      child: Icon(step.icon, color: step.accent, size: 21),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            step.eyebrow.toUpperCase(),
                            style: RunThruTypography.tinyLabel.copyWith(
                              color: step.accent,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${stepIndex + 1} of $total',
                            style: RunThruTypography.tinyLabel,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  step.title,
                  style: RunThruTypography.title.copyWith(
                    color: RunThruTokens.shellInk,
                    fontWeight: FontWeight.w800,
                    height: 1.12,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  step.body,
                  style: RunThruTypography.body.copyWith(
                    color: RunThruTokens.shellInkSoft,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 15),
                if (stackFooter)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: _QuietTextButton(
                          key: skipKey,
                          label: 'Skip tour',
                          onPressed: completing ? null : onSkip,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _StepDots(
                        count: total,
                        index: stepIndex,
                        accent: step.accent,
                      ),
                      const SizedBox(height: 10),
                      _PrimaryOnboardingButton(
                        key: ctaKey,
                        label: step.cta,
                        accent: step.accent,
                        trailingArrow: stepIndex < total - 1,
                        onPressed: completing ? null : onNext,
                      ),
                    ],
                  )
                else
                  Row(
                    children: [
                      _QuietTextButton(
                        key: skipKey,
                        label: 'Skip tour',
                        onPressed: completing ? null : onSkip,
                      ),
                      const Spacer(),
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: _StepDots(
                            count: total,
                            index: stepIndex,
                            accent: step.accent,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      _PrimaryOnboardingButton(
                        key: ctaKey,
                        label: step.cta,
                        accent: step.accent,
                        compact: true,
                        trailingArrow: stepIndex < total - 1,
                        onPressed: completing ? null : onNext,
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CoachCardPointer extends StatelessWidget {
  const _CoachCardPointer({required this.pointerAbove});

  final bool pointerAbove;

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: Offset(0, pointerAbove ? -7 : 7),
      child: Transform.rotate(
        angle: 0.785398,
        child: DecoratedBox(
          key: const ValueKey('coach-tooltip-pointer'),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFECE3CF), Color(0xFFDDD4BF)],
            ),
            borderRadius: BorderRadius.circular(3),
            boxShadow: [
              BoxShadow(
                color: RunThruTokens.shellCream.withValues(alpha: 0.48),
                offset: const Offset(-2, -2),
                blurRadius: 4,
              ),
            ],
          ),
          child: const SizedBox(width: 16, height: 16),
        ),
      ),
    );
  }
}

class _PrimaryOnboardingButton extends StatelessWidget {
  const _PrimaryOnboardingButton({
    super.key,
    required this.label,
    required this.accent,
    required this.onPressed,
    this.compact = false,
    this.trailingArrow = false,
  });

  final String label;
  final Color accent;
  final VoidCallback? onPressed;
  final bool compact;
  final bool trailingArrow;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: 48,
        minWidth: compact ? 0 : double.infinity,
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: RunThruTokens.shellCream,
          disabledBackgroundColor: RunThruTokens.shellInkFaint,
          disabledForegroundColor: RunThruTokens.shellCream,
          elevation: 0,
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 16 : 22,
            vertical: 14,
          ),
          textStyle: RunThruTypography.primaryButton,
          shape: const StadiumBorder(),
        ),
        child: trailingArrow
            ? Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      softWrap: false,
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.arrow_forward_rounded, size: 15),
                ],
              )
            : Text(
                label,
                textAlign: TextAlign.center,
                softWrap: false,
                maxLines: 1,
                overflow: TextOverflow.fade,
              ),
      ),
    );
  }
}

class _QuietTextButton extends StatelessWidget {
  const _QuietTextButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        foregroundColor: RunThruTokens.shellInkSoft,
        textStyle: RunThruTypography.caption.copyWith(
          fontWeight: FontWeight.w800,
        ),
        shape: const StadiumBorder(),
      ),
      child: Text(label),
    );
  }
}

class _StepDots extends StatelessWidget {
  const _StepDots({
    required this.count,
    required this.index,
    required this.accent,
  });

  final int count;
  final int index;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Row(
        key: const ValueKey('onboarding-step-dots'),
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < count; i++)
            AnimatedContainer(
              key: ValueKey('onboarding-step-dot-$i'),
              duration: isReducedMotion(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 180),
              width: i == index ? 18 : 6,
              height: 6,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: i == index
                    ? accent
                    : RunThruTokens.shellInkFaint.withValues(alpha: 0.34),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
        ],
      ),
    );
  }
}

class _EyeHopPathPainter extends CustomPainter {
  const _EyeHopPathPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final baseline = size.height * 0.46;
    final crest = size.height * 0.05;
    final path = Path()
      ..moveTo(size.width * 0.06, baseline)
      ..quadraticBezierTo(size.width * 0.14, crest, size.width * 0.22, baseline)
      ..quadraticBezierTo(size.width * 0.33, crest, size.width * 0.44, baseline)
      ..quadraticBezierTo(size.width * 0.56, crest, size.width * 0.68, baseline)
      ..quadraticBezierTo(
        size.width * 0.81,
        crest,
        size.width * 0.94,
        baseline,
      );

    final paint = Paint()
      ..color = RunThruTokens.shellInkFaint.withValues(alpha: 0.54)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.45
      ..strokeCap = StrokeCap.round;

    const dashWidth = 3.0;
    const gapWidth = 4.5;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + dashWidth).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance += dashWidth + gapWidth;
      }
    }
  }

  @override
  bool shouldRepaint(_EyeHopPathPainter oldDelegate) => false;
}

class _WordChip extends StatelessWidget {
  const _WordChip({required this.text, this.accent, this.muted = false});

  final String text;
  final Color? accent;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final accent = this.accent;
    final children = accent == null
        ? <InlineSpan>[TextSpan(text: text)]
        : <InlineSpan>[
            const TextSpan(text: 're'),
            TextSpan(
              text: 'a',
              style: TextStyle(color: accent),
            ),
            const TextSpan(text: 'ding'),
          ];

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: accent == null ? 11 : 13,
        vertical: accent == null ? 6 : 7,
      ),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [RunThruTokens.shellSandHi, RunThruTokens.shellSandDeep],
        ),
        borderRadius: BorderRadius.circular(10),
        border: accent == null
            ? Border.all(
                color: RunThruTokens.shellCream.withValues(alpha: 0.34),
                width: 0.6,
              )
            : Border.all(color: accent.withValues(alpha: 0.86), width: 2),
        boxShadow: [
          BoxShadow(
            color: RunThruTokens.shellCream.withValues(alpha: 0.64),
            offset: const Offset(-2, -2),
            blurRadius: 5,
          ),
          BoxShadow(
            color: RunThruTokens.shellSandDeep.withValues(alpha: 0.72),
            offset: const Offset(2, 2),
            blurRadius: 6,
          ),
          if (accent != null)
            BoxShadow(
              color: accent.withValues(alpha: 0.32),
              blurRadius: 16,
              spreadRadius: 1.5,
            ),
          if (accent != null)
            BoxShadow(
              color: accent.withValues(alpha: 0.18),
              blurRadius: 24,
              spreadRadius: 3,
            ),
        ],
      ),
      child: RichText(
        textScaler: TextScaler.noScaling,
        text: TextSpan(
          style: RunThruTypography.caption.copyWith(
            color: muted ? RunThruTokens.shellInkFaint : RunThruTokens.shellInk,
            fontWeight: FontWeight.w800,
            height: 1,
          ),
          children: children,
        ),
      ),
    );
  }
}
