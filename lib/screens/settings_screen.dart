import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speedy_boy/design/design.dart';
import 'package:speedy_boy/store/config.dart';
import 'package:speedy_boy/store/models.dart';
import 'package:speedy_boy/widgets/neumorphic_card.dart';
import 'package:speedy_boy/widgets/wpm_slider.dart';

/// Settings screen with neumorphic cards.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configAsync = ref.watch(configProvider);
    final config = configAsync.valueOrNull ?? const AppConfig();
    final notifier = ref.read(configProvider.notifier);

    return Scaffold(
      backgroundColor: SpeedyBoyTokens.shellBase,
      appBar: AppBar(
        backgroundColor: SpeedyBoyTokens.shellBase,
        elevation: 0,
        title: const Text(
          'Settings',
          style: SpeedyBoyTypography.title,
        ),
        iconTheme: const IconThemeData(
          color: SpeedyBoyTokens.shellTextPrimary,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          // ── Reading Speed ──
          NeumorphicCard(
            surface: SpeedyBoySurface.shell,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Reading Speed',
                  style: SpeedyBoyTypography.title,
                ),
                const SizedBox(height: 12),
                WpmSlider(
                  value: config.defaultWpm,
                  onChanged: notifier.setDefaultWpm,
                ),
              ],
            ),
          ),

          // ── PDF Folder ──
          NeumorphicCard(
            surface: SpeedyBoySurface.shell,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'PDF Folder',
                  style: SpeedyBoyTypography.title,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        config.pdfFolderPath ?? 'No folder selected',
                        style: SpeedyBoyTypography.body.copyWith(
                          color: config.pdfFolderPath != null
                              ? SpeedyBoyTokens.shellTextPrimary
                              : SpeedyBoyTokens.shellTextSecondary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: SpeedyBoyTokens.shellAccent,
                        foregroundColor: SpeedyBoyTokens.stageText,
                      ),
                      onPressed: () async {
                        final result =
                            await FilePicker.platform.getDirectoryPath();
                        if (result != null) {
                          await notifier.setPdfFolderPath(
                            result,
                          );
                        }
                      },
                      child: Text(
                        'Browse',
                        style: SpeedyBoyTypography.body.copyWith(
                          color: SpeedyBoyTokens.stageText,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Stereoscopic Depth ──
          NeumorphicCard(
            surface: SpeedyBoySurface.shell,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Spatial Parallax',
                  style: SpeedyBoyTypography.title,
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Parallax Effect',
                      style: SpeedyBoyTypography.body,
                    ),
                    Switch(
                      value: config.stereoscopicEnabled,
                      activeColor: SpeedyBoyTokens.shellAccent,
                      onChanged: notifier.setStereoscopicEnabled,
                    ),
                  ],
                ),
                if (config.stereoscopicEnabled) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Parallax Factor: '
                    '${config.parallaxFactor.toStringAsFixed(1)}',
                    style: SpeedyBoyTypography.body,
                  ),
                  Slider(
                    value: config.parallaxFactor,
                    min: 0.0,
                    max: 2.0,
                    activeColor: SpeedyBoyTokens.shellAccent,
                    onChanged: notifier.setParallaxFactor,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Move your mouse (desktop) or tilt your '
                    'device (mobile) to shift the 3D '
                    'perspective — a magic window effect.',
                    style: SpeedyBoyTypography.caption,
                  ),
                ],
              ],
            ),
          ),

          // ── Anchor Color ──
          NeumorphicCard(
            surface: SpeedyBoySurface.shell,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Anchor Letter Color',
                  style: SpeedyBoyTypography.title,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: List.generate(
                    SpeedyBoyTokens.anchorColors.length,
                    (i) {
                      final color = SpeedyBoyTokens.anchorColors[i];
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
                                    color: SpeedyBoyTokens.shellTextPrimary,
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
                                  color: SpeedyBoyTokens.stageText,
                                  size: 20,
                                )
                              : null,
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  SpeedyBoyTokens
                      .anchorColorNames[config.anchorColorIndex.clamp(
                    0,
                    SpeedyBoyTokens.anchorColorNames.length - 1,
                  )],
                  style: SpeedyBoyTypography.caption,
                ),
              ],
            ),
          ),

          // ── App Info (inset) ──
          const NeumorphicCard(
            surface: SpeedyBoySurface.shell,
            inset: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Speedy Boy',
                  style: SpeedyBoyTypography.title,
                ),
                SizedBox(height: 4),
                Text(
                  'Version 2.0.0',
                  style: SpeedyBoyTypography.caption,
                ),
                SizedBox(height: 4),
                Text(
                  'Speed reading with 3D depth.',
                  style: SpeedyBoyTypography.caption,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
