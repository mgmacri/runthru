import 'dart:developer' as dev;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speedy_boy/design/design.dart';
import 'package:speedy_boy/store/config.dart';
import 'package:speedy_boy/store/models.dart';
import 'package:speedy_boy/widgets/neumorphic_card.dart';
import 'package:speedy_boy/widgets/wpm_slider.dart';

/// Settings screen with neumorphic cards.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _pickFolder(
    BuildContext context,
    ConfigNotifier notifier,
  ) async {
    try {
      // Check storage permission on Android / iOS
      final status = await Permission.storage.status;
      if (status.isDenied) {
        final result = await Permission.storage.request();
        if (result.isPermanentlyDenied && context.mounted) {
          _showPermissionDeniedDialog(context);
          return;
        }
        if (!result.isGranted) return;
      }

      final result = await FilePicker.platform.getDirectoryPath();
      if (result != null) {
        await notifier.setPdfFolderPath(result);
      }
    } on Object catch (e) {
      dev.log('Folder pick failed: $e', name: 'settings');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open folder picker: $e'),
            backgroundColor: SpeedyBoyTokens.shellError,
          ),
        );
      }
    }
  }

  void _showPermissionDeniedDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'Permission Required',
          style: SpeedyBoyTypography.title,
        ),
        content: const Text(
          'Speedy Boy needs file access permission to scan '
          'your PDF folders. Please enable it in Settings.',
          style: SpeedyBoyTypography.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

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
                      onPressed: () => _pickFolder(context, notifier),
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

          // ── Reading Font ──
          NeumorphicCard(
            surface: SpeedyBoySurface.shell,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Reading Font',
                  style: SpeedyBoyTypography.title,
                ),
                const SizedBox(height: 4),
                const Text(
                  'Bundled fonts are guaranteed. System fonts depend on your device.',
                  style: SpeedyBoyTypography.caption,
                ),
                const SizedBox(height: 12),
                _FontPicker(
                  selected: config.fontFamily,
                  onChanged: notifier.setFontFamily,
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

class _FontPicker extends StatelessWidget {
  const _FontPicker({
    required this.selected,
    required this.onChanged,
  });

  final String selected;
  final void Function(String) onChanged;

  @override
  Widget build(BuildContext context) {
    const fonts = SpeedyBoyTypography.availableFonts;
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
          style: SpeedyBoyTypography.caption.copyWith(
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
              ? SpeedyBoyTokens.shellAccent.withAlpha(30)
              : SpeedyBoyTokens.shellBase,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? SpeedyBoyTokens.shellAccent
                : SpeedyBoyTokens.shellTextSecondary.withAlpha(40),
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
                  color: SpeedyBoyTokens.shellTextPrimary,
                ),
              ),
            ),
            if (isSelected)
              const Icon(
                Icons.check_circle,
                color: SpeedyBoyTokens.shellAccent,
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
              ? SpeedyBoyTokens.shellAccent.withAlpha(30)
              : SpeedyBoyTokens.shellBase,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? SpeedyBoyTokens.shellAccent
                : SpeedyBoyTokens.shellTextSecondary.withAlpha(40),
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
                ? SpeedyBoyTokens.shellAccent
                : SpeedyBoyTokens.shellTextPrimary,
          ),
        ),
      ),
    );
  }
}
