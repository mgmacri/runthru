import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runthru/core/logger.dart';
import 'package:runthru/core/reading_goal_presets.dart';
import 'package:runthru/core/wcag_contrast.dart';
import 'package:runthru/design/design.dart';
import 'package:runthru/features/settings/widgets/pacing_panel.dart';
import 'package:runthru/features/settings/widgets/spacing_controls.dart';
import 'package:runthru/services/purchase_service.dart';
import 'package:runthru/store/config.dart';
import 'package:runthru/store/models.dart';
import 'package:runthru/widgets/neumorphic_card.dart';
import 'package:runthru/widgets/wpm_slider.dart';

/// Settings screen with neumorphic cards.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({
    super.key,
    this.focusGoogleDriveBrowserSetting = false,
    this.focusRequestId,
  });

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
    final hasPremium = config.hasPremium;

    return Scaffold(
      backgroundColor: RunThruTokens.shellBase,
      appBar: AppBar(
        backgroundColor: RunThruTokens.shellBase,
        elevation: 0,
        title: const Text('Settings', style: RunThruTypography.title),
        iconTheme: const IconThemeData(color: RunThruTokens.shellTextPrimary),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          // ── Reading Goal ──
          NeumorphicCard(
            surface: RunThruSurface.shell,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Reading Goal', style: RunThruTypography.title),
                const SizedBox(height: 4),
                Text(
                  'Choose a preset to adjust speed and room settings.',
                  style: RunThruTypography.caption.copyWith(
                    color: RunThruTokens.shellTextSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                _ReadingGoalSelector(
                  selected: config.readingGoalPreset,
                  currentWpm: config.defaultWpm,
                  currentParallax: config.parallaxIntensity,
                  hasPremium: hasPremium,
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
                  onChanged: (enabled) => notifier.setGoogleDriveAccessMode(
                    enabled
                        ? GoogleDriveAccessMode.fullDriveBrowser
                        : GoogleDriveAccessMode.selectedFilesOnly,
                  ),
                ),
              ],
            ),
          ),

          // ── 3D Mode (Premium only — ALL platforms) ──
          if (hasPremium)
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
                  _ParallaxIntensitySelector(
                    selected: config.parallaxIntensity,
                    onChanged: notifier.setParallaxIntensity,
                  ),
                ],
              ),
            ),

          // ── Anchor Color (Premium only) ──
          if (hasPremium)
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
                      return GestureDetector(
                        onTap: () => notifier.setAnchorColorIndex(i),
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

          // ── Reading Font (Premium only) ──
          if (hasPremium)
            NeumorphicCard(
              surface: RunThruSurface.shell,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Reading Font', style: RunThruTypography.title),
                  const SizedBox(height: 4),
                  const Text(
                    'Bundled fonts are guaranteed. System fonts depend on your device.',
                    style: RunThruTypography.caption,
                  ),
                  const SizedBox(height: 12),
                  _FontPicker(
                    selected: config.fontFamily,
                    onChanged: notifier.setFontFamily,
                  ),
                ],
              ),
            ),

          // ── Upgrade to Premium (free users only) ──
          if (!hasPremium)
            NeumorphicCard(
              surface: RunThruSurface.shell,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Unlock 3D Reading',
                    style: RunThruTypography.title,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Get the immersive 3D cube viewport, head-tracking '
                    'parallax, custom fonts, and reading range selection.',
                    style: RunThruTypography.body.copyWith(
                      color: RunThruTokens.shellTextSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: RunThruTokens.shellAccent,
                      foregroundColor: RunThruTokens.shellBase,
                    ),
                    onPressed: () =>
                        ref.read(purchaseServiceProvider).purchasePremium(),
                    child: Text(
                      'Upgrade',
                      style: RunThruTypography.body.copyWith(
                        color: RunThruTokens.shellBase,
                      ),
                    ),
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
                  'Speed reading with 3D depth.',
                  style: RunThruTypography.caption,
                ),
              ],
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
    final system = fonts.where((f) => !f.isBundled).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Bundled fonts
        ...bundled.map(_fontTile),
        const SizedBox(height: 8),
        Text(
          'System Fonts',
          style: RunThruTypography.caption.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        // System fonts in a wrap for compactness
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: system.map(_fontChip).toList(),
        ),
      ],
    );
  }

  Widget _fontTile(FontChoice font) {
    final isSelected = font.family == selected;
    return GestureDetector(
      onTap: () => onChanged(font.family),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? RunThruTokens.shellAccent.withAlpha(30)
              : RunThruTokens.shellBase,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? RunThruTokens.shellAccent
                : RunThruTokens.shellTextSecondary.withAlpha(40),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                font.displayName,
                style: TextStyle(
                  fontFamily: font.family,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: RunThruTokens.shellTextPrimary,
                ),
              ),
            ),
            if (isSelected)
              const Icon(
                Icons.check_circle,
                color: RunThruTokens.shellAccent,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }

  Widget _fontChip(FontChoice font) {
    final isSelected = font.family == selected;
    return GestureDetector(
      onTap: () => onChanged(font.family),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected
              ? RunThruTokens.shellAccent.withAlpha(30)
              : RunThruTokens.shellBase,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? RunThruTokens.shellAccent
                : RunThruTokens.shellTextSecondary.withAlpha(40),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Text(
          font.displayName,
          style: TextStyle(
            fontFamily: font.family,
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            color: isSelected
                ? RunThruTokens.shellAccent
                : RunThruTokens.shellTextPrimary,
          ),
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

/// Segmented selector for reading goal presets (3 presets + Custom indicator).
class _ReadingGoalSelector extends StatefulWidget {
  const _ReadingGoalSelector({
    required this.selected,
    required this.currentWpm,
    required this.currentParallax,
    required this.hasPremium,
    required this.onChanged,
  });

  final ReadingGoalPreset? selected;
  final int currentWpm;
  final ParallaxIntensity currentParallax;
  final bool hasPremium;
  final void Function(ReadingGoalConfig) onChanged;

  @override
  State<_ReadingGoalSelector> createState() => _ReadingGoalSelectorState();
}

class _ReadingGoalSelectorState extends State<_ReadingGoalSelector> {
  int _focusedIndex = 0;
  final FocusNode _focusNode = FocusNode();

  /// Whether user has manually changed WPM/parallax away from any preset.
  bool get _isCustom {
    if (widget.selected == null) return true;
    final match = readingGoalConfigs.where(
      (c) =>
          c.preset == widget.selected &&
          c.wpm == widget.currentWpm &&
          // Skip parallax check for free users — parallax is gated to none
          (widget.hasPremium
              ? c.parallaxIntensity == widget.currentParallax
              : true),
    );
    return match.isEmpty;
  }

  /// 3 presets + Custom = 4 segments.
  static const _customIndex = 3;
  int get _segmentCount => readingGoalConfigs.length + 1;

  @override
  void initState() {
    super.initState();
    if (_isCustom) {
      _focusedIndex = _customIndex;
    } else {
      _focusedIndex = readingGoalConfigs.indexWhere(
        (c) => c.preset == widget.selected,
      );
      if (_focusedIndex < 0) _focusedIndex = _customIndex;
    }
  }

  void _moveFocus(int delta) {
    setState(() {
      _focusedIndex = (_focusedIndex + delta).clamp(0, _segmentCount - 1);
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
      if (_focusedIndex < readingGoalConfigs.length) {
        widget.onChanged(readingGoalConfigs[_focusedIndex]);
      }
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
    final isCustom = _isCustom;
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _handleKey,
      child: Row(
        children: List.generate(_segmentCount, (index) {
          final bool isSelected;
          final String label;
          final String semanticsLabel;
          final String hint;
          final VoidCallback? onTap;

          if (index < readingGoalConfigs.length) {
            final goal = readingGoalConfigs[index];
            isSelected = !isCustom && goal.preset == widget.selected;
            // Short labels for compact segments
            label = switch (goal.preset) {
              ReadingGoalPreset.deepRead => 'Deep',
              ReadingGoalPreset.comfortable => 'Comfort',
              ReadingGoalPreset.quickScan => 'Quick',
            };
            semanticsLabel = goal.name;
            hint = goal.description;
            onTap = () => widget.onChanged(goal);
          } else {
            // Custom segment (read-only indicator)
            isSelected = isCustom;
            label = 'Custom';
            semanticsLabel = 'Custom';
            hint = 'Manual WPM or room settings';
            onTap = null;
          }

          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Semantics(
                label: semanticsLabel,
                hint: hint,
                selected: isSelected,
                inMutuallyExclusiveGroup: true,
                child: GestureDetector(
                  onTap: onTap,
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
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          label,
                          maxLines: 1,
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
            ),
          );
        }),
      ),
    );
  }
}
