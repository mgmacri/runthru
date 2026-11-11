import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:runthru/core/logger.dart';
import 'package:runthru/core/reading_goal_presets.dart';
import 'package:runthru/core/wcag_contrast.dart';
import 'package:runthru/design/design.dart';
import 'package:runthru/features/content/providers/google_drive_auth_provider.dart';
import 'package:runthru/features/settings/widgets/pacing_panel.dart';
import 'package:runthru/features/settings/widgets/spacing_controls.dart';
import 'package:runthru/store/config.dart';
import 'package:runthru/store/models.dart';
import 'package:runthru/widgets/neumorphic_card.dart';
import 'package:runthru/widgets/runthru_shell_widgets.dart';
import 'package:runthru/widgets/unlock_sheet.dart';
import 'package:runthru/widgets/wpm_slider.dart';

/// Settings screen with neumorphic cards.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({
    super.key,
    this.focusGoogleDriveBrowserSetting = false,
    this.focusRequestId,
    this.showBack = false,
  });

  /// Shows a back button in the header. True when Settings is pushed over
  /// the reader (the "Aa" button) rather than shown as a home-shell tab.
  final bool showBack;

  /// Scrolls directly to the Google Drive browser setting after build.
  final bool focusGoogleDriveBrowserSetting;

  /// Unique request token for repeated focus requests.
  final String? focusRequestId;

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _googleDriveBrowserSettingKey = GlobalKey();
  String? _handledFocusRequestId;

  @override
  void initState() {
    super.initState();
    _scheduleGoogleDriveBrowserFocus();
  }

  @override
  void didUpdateWidget(covariant SettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusGoogleDriveBrowserSetting &&
        (widget.focusRequestId != oldWidget.focusRequestId ||
            !oldWidget.focusGoogleDriveBrowserSetting)) {
      _scheduleGoogleDriveBrowserFocus();
    }
  }

  void _scheduleGoogleDriveBrowserFocus() {
    final requestId = widget.focusRequestId ?? 'initial';
    if (!widget.focusGoogleDriveBrowserSetting ||
        _handledFocusRequestId == requestId) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _handledFocusRequestId == requestId) return;
      final context = _googleDriveBrowserSettingKey.currentContext;
      if (context == null) return;
      _handledFocusRequestId = requestId;
      Scrollable.ensureVisible(
        context,
        duration: isReducedMotion(context)
            ? Duration.zero
            : const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        alignment: 0.08,
      );
    });
  }

  void _showLogViewer(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: RunThruTokens.shellBase,
      builder: (context) {
        final logs = AppLogger.entries;
        final text = logs.isEmpty ? '(no logs yet)' : logs.join('\n');
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.3,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Debug Logs', style: RunThruTypography.title),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.copy, size: 18),
                            tooltip: 'Copy to clipboard',
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: text));
                              Navigator.of(context).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Logs copied to clipboard'),
                                ),
                              );
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Divider(),
                Expanded(
                  child: SingleChildScrollView(
                    controller: scrollController,
                    reverse: true,
                    padding: const EdgeInsets.all(12),
                    child: SelectableText(
                      text,
                      style: RunThruTypography.caption.copyWith(
                        fontFamily: 'monospace',
                        fontSize: 10,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final configAsync = ref.watch(configProvider);
    final config = configAsync.valueOrNull ?? const AppConfig();
    final notifier = ref.read(configProvider.notifier);

    return Scaffold(
      backgroundColor: RunThruTokens.shellBase,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            RunThruScreenHeader(
              title: 'Settings',
              subtitle: 'Reading comfort and sources',
              leading: widget.showBack
                  ? RunThruHeaderIconButton(
                      icon: Icons.arrow_back_ios_new_rounded,
                      tooltip: 'Back to reading',
                      onPressed: () => Navigator.of(context).pop(),
                    )
                  : null,
            ),
            // ── Reading Goal ──
            NeumorphicCard(
              surface: RunThruSurface.shell,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Reading Goal', style: RunThruTypography.title),
                  const SizedBox(height: 4),
                  Text(
                    // The room is part of RunThru Unlock; presets only set it
                    // for owners.
                    config.hasPremium
                        ? 'Choose a preset to set reading speed, word pacing '
                              'and the 3D room.'
                        : 'Choose a preset to set reading speed and word '
                              'pacing.',
                    style: RunThruTypography.caption.copyWith(
                      color: RunThruTokens.shellTextSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _ReadingGoalSelector(
                    inEffect: config.readingGoalInEffect,
                    customized: config.readingGoalCustomized,
                    onChanged: notifier.applyReadingGoalPreset,
                  ),
                ],
              ),
            ),

            // ── Reading Speed ──
            NeumorphicCard(
              surface: RunThruSurface.shell,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Reading Speed', style: RunThruTypography.title),
                  const SizedBox(height: 12),
                  WpmSlider(
                    value: config.defaultWpm,
                    onChanged: notifier.setDefaultWpm,
                  ),
                  // P1 Grade A — shortened WPM advisory text
                  if (config.defaultWpm > 350)
                    Semantics(
                      liveRegion: true,
                      child: const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text(
                          'Best for scanning familiar text',
                          style: RunThruTypography.caption,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // ── Word Pacing ──
            const PacingPanel(),

            // ── Reading Comfort ──
            const SpacingControls(),

            NeumorphicCard(
              surface: RunThruSurface.shell,
              child: Row(
                children: [
                  const Icon(
                    Icons.center_focus_strong_rounded,
                    size: 22,
                    color: RunThruTokens.shellAccent,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Focus Mode',
                          style: RunThruTypography.title,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Hide reading controls and use gestures for pause, sentence steps, and pace.',
                          style: RunThruTypography.caption.copyWith(
                            color: RunThruTokens.shellTextSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Switch.adaptive(
                    value: config.focusModeEnabled,
                    activeThumbColor: RunThruTokens.shellAccent,
                    activeTrackColor: RunThruTokens.shellAccent.withValues(
                      alpha: 0.34,
                    ),
                    onChanged: notifier.setFocusModeEnabled,
                  ),
                ],
              ),
            ),

            // ── Chapter moments ──
            NeumorphicCard(
              surface: RunThruSurface.shell,
              child: MergeSemantics(
                child: Row(
                  children: [
                    const Icon(
                      Icons.auto_stories_rounded,
                      size: 22,
                      color: RunThruTokens.shellAccent,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Chapter moments',
                            style: RunThruTypography.title,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Announce each chapter with a title card and mark '
                            'the end of a chapter before moving on.',
                            style: RunThruTypography.caption.copyWith(
                              color: RunThruTokens.shellTextSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Switch.adaptive(
                      value: config.chapterMoments,
                      activeThumbColor: RunThruTokens.shellAccent,
                      activeTrackColor: RunThruTokens.shellAccent.withValues(
                        alpha: 0.34,
                      ),
                      onChanged: notifier.setChapterMoments,
                    ),
                  ],
                ),
              ),
            ),

            // ── Reading Font ──
            NeumorphicCard(
              surface: RunThruSurface.shell,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Reading Font', style: RunThruTypography.title),
                  const SizedBox(height: 4),
                  Text(
                    'Atkinson Hyperlegible is optimised for fast single-fixation word recognition.',
                    style: RunThruTypography.caption.copyWith(
                      color: RunThruTokens.shellTextSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _FontPicker(
                    selected: config.readingFontFamily,
                    onChanged: notifier.setReadingFontFamily,
                  ),
                ],
              ),
            ),

            // R-04: hidden when the build has no Drive OAuth config.
            if (ref.watch(googleDriveAvailableProvider))
              NeumorphicCard(
                key: _googleDriveBrowserSettingKey,
                surface: RunThruSurface.shell,
                child: Row(
                  children: [
                    const Icon(
                      Icons.manage_search_rounded,
                      size: 22,
                      color: RunThruTokens.shellAccent,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Use full Drive browser',
                            style: RunThruTypography.title,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Browse supported files across Google Drive. This requires broader Drive access and may not be available in some organizations.',
                            style: RunThruTypography.caption.copyWith(
                              color: RunThruTokens.shellTextSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Switch.adaptive(
                      value:
                          config.googleDriveAccessMode ==
                          GoogleDriveAccessMode.fullDriveBrowser,
                      activeThumbColor: RunThruTokens.shellAccent,
                      activeTrackColor: RunThruTokens.shellAccent,
                      onChanged: (enabled) => notifier.setGoogleDriveAccessMode(
                        enabled
                            ? GoogleDriveAccessMode.fullDriveBrowser
                            : GoogleDriveAccessMode.selectedFilesOnly,
                      ),
                    ),
                  ],
                ),
              ),

            // ── 3D Mode ──
            NeumorphicCard(
              surface: RunThruSurface.shell,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('3D Room Mode', style: RunThruTypography.title),
                  const SizedBox(height: 4),
                  Text(
                    'Controls the 3D room depth and parallax effect.',
                    style: RunThruTypography.caption.copyWith(
                      color: RunThruTokens.shellTextSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Part of RunThru Unlock.
                  if (config.hasPremium)
                    _ParallaxIntensitySelector(
                      selected: config.parallaxIntensity,
                      onChanged: notifier.setParallaxIntensity,
                    )
                  else
                    Align(
                      alignment: Alignment.centerLeft,
                      child: RunThruPrimaryButton(
                        icon: Icons.lock_open,
                        label: 'Unlock the 3D room',
                        onPressed: () => showUnlockSheet(context),
                      ),
                    ),
                ],
              ),
            ),

            // ── Anchor Color ──
            NeumorphicCard(
              surface: RunThruSurface.shell,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Anchor Letter Color',
                    style: RunThruTypography.title,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: List.generate(RunThruTokens.anchorColors.length, (
                      i,
                    ) {
                      final color = RunThruTokens.anchorColors[i];
                      final selected = config.anchorColorIndex == i;
                      return Semantics(
                        button: true,
                        selected: selected,
                        label:
                            'Select: anchor color '
                            '${RunThruTokens.anchorColorNames[i]}',
                        // excludeSemantics drops the child's tap action, so
                        // the semantic tap must be supplied here.
                        onTap: () => notifier.setAnchorColorIndex(i),
                        excludeSemantics: true,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => notifier.setAnchorColorIndex(i),
                          child: SizedBox.square(
                            dimension: RunThruA11y.minTapTarget,
                            child: Center(
                              child: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle,
                                  border: selected
                                      ? Border.all(
                                          color: RunThruTokens.shellTextPrimary,
                                          width: 3,
                                        )
                                      : null,
                                  boxShadow: selected
                                      ? [
                                          BoxShadow(
                                            color: color.withAlpha(120),
                                            blurRadius: 8,
                                            spreadRadius: 2,
                                          ),
                                        ]
                                      : null,
                                ),
                                child: selected
                                    ? const Icon(
                                        Icons.check,
                                        color: RunThruTokens.shellTextPrimary,
                                        size: 20,
                                      )
                                    : null,
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    RunThruTokens.anchorColorNames[config.anchorColorIndex
                        .clamp(0, RunThruTokens.anchorColorNames.length - 1)],
                    style: RunThruTypography.caption,
                  ),
                  // P14 Grade C — live preview of anchor color on stage surface
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: const BoxDecoration(
                      color: RunThruTokens.stageBase,
                      borderRadius: BorderRadius.all(Radius.circular(8)),
                    ),
                    child: Center(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: 'rea',
                              style: RunThruTypography.readingWord(24),
                            ),
                            TextSpan(
                              text: 'd',
                              style: RunThruTypography.readingAnchor(
                                24,
                                color:
                                    RunThruTokens.anchorColors[config
                                        .anchorColorIndex
                                        .clamp(
                                          0,
                                          RunThruTokens.anchorColors.length - 1,
                                        )],
                              ),
                            ),
                            TextSpan(
                              text: 'ing',
                              style: RunThruTypography.readingWord(24),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // P14 Grade C — contrast warning tiers
                  Builder(
                    builder: (context) {
                      final anchorColor =
                          RunThruTokens.anchorColors[config.anchorColorIndex
                              .clamp(0, RunThruTokens.anchorColors.length - 1)];
                      final ratio = WcagContrast.contrastRatio(
                        anchorColor,
                        RunThruTokens.stageBase,
                      );
                      if (ratio >= 4.5) return const SizedBox.shrink();
                      final isDanger = ratio < 3.0;
                      return Semantics(
                        liveRegion: true,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            isDanger
                                ? 'This color is very hard to see — consider a darker option'
                                : 'This color may be hard to see at speed',
                            style: RunThruTypography.caption.copyWith(
                              color: isDanger
                                  ? RunThruTokens.shellError
                                  : RunThruTokens.shellProcessing,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),

            // ── RunThru Unlock (purchase + restore, store requirement) ──
            NeumorphicCard(
              surface: RunThruSurface.shell,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('RunThru Unlock', style: RunThruTypography.title),
                  const SizedBox(height: 4),
                  Text(
                    config.hasPremium
                        ? 'Active. Thank you for supporting RunThru.'
                        : 'One payment, no subscription. Adds Reading Wins, '
                              'page ranges and the 3D room.',
                    style: RunThruTypography.caption.copyWith(
                      color: RunThruTokens.shellTextSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  RunThruPrimaryButton(
                    icon: config.hasPremium ? Icons.check : Icons.lock_open,
                    label: config.hasPremium
                        ? 'View purchase'
                        : 'Unlock or restore purchase',
                    onPressed: () => showUnlockSheet(context),
                  ),
                ],
              ),
            ),

            // ── App Info (inset) ──
            const NeumorphicCard(
              surface: RunThruSurface.shell,
              inset: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('RunThru', style: RunThruTypography.title),
                  SizedBox(height: 4),
                  Text('Version 2.0.0', style: RunThruTypography.caption),
                  SizedBox(height: 4),
                  Text(
                    'Paced reading for focus.',
                    style: RunThruTypography.caption,
                  ),
                ],
              ),
            ),

            // ── Privacy policy (store requirement, R-07) ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: TextButton.icon(
                  onPressed: () => context.push('/settings/privacy'),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(
                      RunThruA11y.minTapTarget,
                      RunThruA11y.minTapTarget,
                    ),
                  ),
                  icon: const Icon(
                    Icons.privacy_tip_outlined,
                    size: 16,
                    color: RunThruTokens.shellTextSecondary,
                  ),
                  label: Text(
                    'Privacy Policy',
                    style: RunThruTypography.caption.copyWith(
                      color: RunThruTokens.shellTextSecondary,
                    ),
                  ),
                ),
              ),
            ),

            // ── Debug Logs ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: TextButton.icon(
                  onPressed: () => _showLogViewer(context),
                  icon: const Icon(
                    Icons.bug_report,
                    size: 16,
                    color: RunThruTokens.shellTextSecondary,
                  ),
                  label: Text(
                    'View Debug Logs',
                    style: RunThruTypography.caption.copyWith(
                      color: RunThruTokens.shellTextSecondary,
                    ),
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

/// Segmented selector for [ParallaxIntensity].
///
/// Visible on ALL platforms — per Rule 6, 3D mode is never platform-gated.
/// Sensor-dependent head tracking is a separate concern; this toggle controls
/// whether the 3D room renders.
///
/// Supports keyboard navigation: arrow keys move focus, Enter/Space selects.
class _ParallaxIntensitySelector extends StatefulWidget {
  const _ParallaxIntensitySelector({
    required this.selected,
    required this.onChanged,
  });

  final ParallaxIntensity selected;
  final void Function(ParallaxIntensity) onChanged;

  static const _options = [
    (
      value: ParallaxIntensity.none,
      label: 'None',
      hint: 'Flat background, no 3D room',
    ),
    (
      value: ParallaxIntensity.off,
      label: 'Off',
      hint: 'Static 3D room, no motion',
    ),
    (
      value: ParallaxIntensity.subtle,
      label: 'Subtle',
      hint: 'Gentle parallax effect',
    ),
    (
      value: ParallaxIntensity.full,
      label: 'Full',
      hint: 'Full parallax effect',
    ),
  ];

  @override
  State<_ParallaxIntensitySelector> createState() =>
      _ParallaxIntensitySelectorState();
}

class _ParallaxIntensitySelectorState
    extends State<_ParallaxIntensitySelector> {
  int _focusedIndex = 0;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusedIndex = _ParallaxIntensitySelector._options.indexWhere(
      (o) => o.value == widget.selected,
    );
    if (_focusedIndex < 0) _focusedIndex = 0;
  }

  @override
  void didUpdateWidget(_ParallaxIntensitySelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected) {
      final idx = _ParallaxIntensitySelector._options.indexWhere(
        (o) => o.value == widget.selected,
      );
      if (idx >= 0) _focusedIndex = idx;
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _moveFocus(int delta) {
    setState(() {
      _focusedIndex = (_focusedIndex + delta).clamp(
        0,
        _ParallaxIntensitySelector._options.length - 1,
      );
    });
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _moveFocus(-1);
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _moveFocus(1);
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.space) {
      widget.onChanged(
        _ParallaxIntensitySelector._options[_focusedIndex].value,
      );
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _handleKey,
      child: Row(
        children: List.generate(_ParallaxIntensitySelector._options.length, (
          index,
        ) {
          final option = _ParallaxIntensitySelector._options[index];
          final isSelected = option.value == widget.selected;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Semantics(
                label: option.label,
                hint: option.hint,
                selected: isSelected,
                inMutuallyExclusiveGroup: true,
                child: GestureDetector(
                  onTap: () => widget.onChanged(option.value),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: isSelected
                        ? RunThruDecorations.insetDecoration(
                            RunThruSurface.shell,
                            size: RunThruShadowSize.small,
                            borderRadius: 10,
                          )
                        : RunThruDecorations.raisedDecoration(
                            RunThruSurface.shell,
                            size: RunThruShadowSize.small,
                            borderRadius: 10,
                          ),
                    alignment: Alignment.center,
                    child: ExcludeSemantics(
                      child: Text(
                        option.label,
                        style: RunThruTypography.caption.copyWith(
                          fontWeight: isSelected
                              ? FontWeight.w700
                              : FontWeight.w400,
                          color: isSelected
                              ? RunThruTokens.shellAccent
                              : RunThruTokens.shellTextSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// Segmented selector for reading goal presets: the 3 goals, then Custom.
///
/// The goal in effect is pressed in. Custom is a status, not a button: it
/// lights up by itself once a setting the chosen goal sets is changed by
/// hand, and nothing is lit before a goal has been chosen.
class _ReadingGoalSelector extends StatefulWidget {
  const _ReadingGoalSelector({
    required this.inEffect,
    required this.customized,
    required this.onChanged,
  });

  /// The chosen goal while every setting it sets is still its own.
  final ReadingGoalPreset? inEffect;

  /// A goal was chosen and one of its settings has been changed since.
  final bool customized;

  final void Function(ReadingGoalConfig) onChanged;

  @override
  State<_ReadingGoalSelector> createState() => _ReadingGoalSelectorState();
}

class _ReadingGoalSelectorState extends State<_ReadingGoalSelector> {
  int _focusedIndex = 0;
  final FocusNode _focusNode = FocusNode();

  /// Keyboard focus starts on the goal in effect (the first goal if none).
  int get _inEffectIndex {
    final index = readingGoalConfigs.indexWhere(
      (c) => c.preset == widget.inEffect,
    );
    return index < 0 ? 0 : index;
  }

  @override
  void initState() {
    super.initState();
    _focusedIndex = _inEffectIndex;
  }

  @override
  void didUpdateWidget(_ReadingGoalSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.inEffect != null && widget.inEffect != oldWidget.inEffect) {
      _focusedIndex = _inEffectIndex;
    }
  }

  /// Moves between the goals only: Custom cannot be chosen.
  void _moveFocus(int delta) {
    setState(() {
      _focusedIndex = (_focusedIndex + delta).clamp(
        0,
        readingGoalConfigs.length - 1,
      );
    });
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _moveFocus(-1);
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _moveFocus(1);
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.space) {
      widget.onChanged(readingGoalConfigs[_focusedIndex]);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _handleKey,
      child: Row(
        children: [
          for (final goal in readingGoalConfigs)
            _ReadingGoalSegment(
              // Short labels for compact segments
              label: switch (goal.preset) {
                ReadingGoalPreset.deepRead => 'Deep',
                ReadingGoalPreset.comfortable => 'Comfort',
                ReadingGoalPreset.quickScan => 'Quick',
              },
              semanticsLabel: goal.name,
              hint: goal.description,
              selected: goal.preset == widget.inEffect,
              onTap: () => widget.onChanged(goal),
            ),
          _ReadingGoalSegment(
            label: 'Custom',
            semanticsLabel: 'Custom',
            hint: 'Lights up when you change a setting after choosing a goal',
            selected: widget.customized,
          ),
        ],
      ),
    );
  }
}

/// One segment of [_ReadingGoalSelector]: raised, or pressed in while it is
/// selected. Without [onTap] (Custom) it is a status and is drawn flat
/// while off, so it never looks like a button that does nothing.
class _ReadingGoalSegment extends StatelessWidget {
  const _ReadingGoalSegment({
    required this.label,
    required this.semanticsLabel,
    required this.hint,
    required this.selected,
    this.onTap,
  });

  final String label;
  final String semanticsLabel;
  final String hint;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final BoxDecoration decoration;
    if (selected) {
      decoration = RunThruDecorations.insetDecoration(
        RunThruSurface.shell,
        size: RunThruShadowSize.small,
        borderRadius: 10,
      );
    } else if (onTap != null) {
      decoration = RunThruDecorations.raisedDecoration(
        RunThruSurface.shell,
        size: RunThruShadowSize.small,
        borderRadius: 10,
      );
    } else {
      decoration = BoxDecoration(
        color: RunThruTokens.shellBase,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: RunThruTokens.shellDivider),
      );
    }

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Semantics(
          label: semanticsLabel,
          hint: hint,
          button: onTap != null,
          selected: selected,
          inMutuallyExclusiveGroup: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: AnimatedContainer(
              duration: isReducedMotion(context)
                  ? Duration.zero
                  : RunThruAnimations.cardPressDuration,
              curve: RunThruAnimations.cardPressCurve,
              constraints: const BoxConstraints(
                minHeight: RunThruA11y.minTapTarget,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              alignment: Alignment.center,
              decoration: decoration,
              child: ExcludeSemantics(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: RunThruTypography.caption.copyWith(
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                      color: selected
                          ? RunThruTokens.shellAccent
                          : RunThruTokens.shellTextSecondary,
                    ),
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

class _FontPicker extends StatelessWidget {
  const _FontPicker({required this.selected, required this.onChanged});

  final String selected;
  final void Function(String) onChanged;

  @override
  Widget build(BuildContext context) {
    const fonts = RunThruTypography.availableFonts;
    final bundled = fonts.where((f) => f.isBundled).toList();
    final system = fonts
        .where((f) => !f.isBundled && _systemFontInstalled(f.family))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...bundled.map(_tile),
        const SizedBox(height: 8),
        Text(
          'System Fonts',
          style: RunThruTypography.caption.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Wrap(spacing: 6, runSpacing: 6, children: system.map(_chip).toList()),
      ],
    );
  }

  Widget _tile(FontChoice font) {
    final isSelected = font.family == selected;
    return GestureDetector(
      onTap: () => onChanged(font.family),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? RunThruTokens.shellAccent.withValues(alpha: 0.12)
              : RunThruTokens.shellBase,
          border: Border.all(
            color: isSelected
                ? RunThruTokens.shellAccent
                : RunThruTokens.shellDivider,
            width: isSelected ? 1.5 : 1.0,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                font.displayName,
                style: TextStyle(
                  fontFamily: font.family,
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                  color: RunThruTokens.shellInk,
                ),
              ),
            ),
            Text(
              'The quick brown fox',
              style: TextStyle(
                fontFamily: font.family,
                fontSize: 12,
                color: RunThruTokens.shellInkSoft,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(FontChoice font) {
    final isSelected = font.family == selected;
    return GestureDetector(
      onTap: () => onChanged(font.family),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? RunThruTokens.shellAccent.withValues(alpha: 0.12)
              : RunThruTokens.shellBase,
          border: Border.all(
            color: isSelected
                ? RunThruTokens.shellAccent
                : RunThruTokens.shellDivider,
            width: isSelected ? 1.5 : 1.0,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          font.displayName,
          style: TextStyle(
            fontFamily: font.family,
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
            color: isSelected
                ? RunThruTokens.shellAccent
                : RunThruTokens.shellInkSoft,
          ),
        ),
      ),
    );
  }
}

/// System fonts the current platform actually ships. Offering a font the
/// device does not have silently falls back to the default, which looks
/// like the setting is broken.
bool _systemFontInstalled(String family) {
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      return const {'Roboto', 'serif', 'monospace'}.contains(family);
    case TargetPlatform.iOS:
      return const {
        'Helvetica Neue',
        'Helvetica',
        'Arial',
        'San Francisco',
        'Georgia',
        'Times New Roman',
        'Palatino',
        'Courier New',
        'Verdana',
        'Trebuchet MS',
        'Futura',
        'Gill Sans',
        'Optima',
        'Avenir',
        'Avenir Next',
      }.contains(family);
    case TargetPlatform.fuchsia:
    case TargetPlatform.linux:
    case TargetPlatform.macOS:
    case TargetPlatform.windows:
      return family != 'serif' && family != 'monospace';
  }
}
