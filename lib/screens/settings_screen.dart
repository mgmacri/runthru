import 'dart:io' show Directory, File, Platform;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speedy_boy/core/logger.dart';
import 'package:speedy_boy/design/design.dart';
import 'package:speedy_boy/services/purchase_service.dart';
import 'package:speedy_boy/store/config.dart';
import 'package:speedy_boy/store/models.dart';
import 'package:speedy_boy/widgets/font_size_slider.dart';
import 'package:speedy_boy/widgets/neumorphic_card.dart';
import 'package:speedy_boy/widgets/wpm_slider.dart';

/// Settings screen with neumorphic cards.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static bool get _isIos {
    if (kIsWeb) return false;
    return Platform.isIOS;
  }

  Future<void> _pickFolder(
    BuildContext context,
    ConfigNotifier notifier,
  ) async {
    try {
      appLog('settings', '_pickFolder — isIos=$_isIos');

      if (_isIos) {
        await _pickPdfsIos(context, notifier);
        return;
      }

      // Android / desktop: pick a directory
      final status = await Permission.storage.status;
      appLog('settings', 'storage permission status=$status');
      if (status.isDenied) {
        final result = await Permission.storage.request();
        appLog('settings', 'storage permission request result=$result');
        if (result.isPermanentlyDenied && context.mounted) {
          _showPermissionDeniedDialog(context);
          return;
        }
        if (!result.isGranted) return;
      }

      appLog('settings', 'calling FilePicker.getDirectoryPath()…');
      final result = await FilePicker.platform.getDirectoryPath();
      appLog('settings', 'FilePicker result=$result');
      if (result != null) {
        await notifier.setPdfFolderPath(result);
        appLog('settings', 'folder path saved to config');
      }
    } on Object catch (e) {
      appLog('settings', 'Folder pick failed: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open file picker: $e'),
            backgroundColor: SpeedyBoyTokens.shellError,
          ),
        );
      }
    }
  }

  /// iOS: pick a folder, use native security-scoped access to list and copy
  /// PDF files to app-local storage. Falls back to multi-file picker if
  /// directory access fails.
  Future<void> _pickPdfsIos(
    BuildContext context,
    ConfigNotifier notifier,
  ) async {
    appLog('settings', 'iOS: calling getDirectoryPath()…');
    final selectedPath = await FilePicker.platform.getDirectoryPath();
    appLog('settings', 'iOS: getDirectoryPath result=$selectedPath');

    if (selectedPath == null) {
      appLog('settings', 'iOS: user cancelled');
      return;
    }

    // Use native platform channel for security-scoped directory access.
    final docsDir = await getApplicationDocumentsDirectory();
    final pdfDirPath = '${docsDir.path}/pdfs';

    try {
      const channel = MethodChannel('com.speedyboy/ios_file_access');
      final result = await channel.invokeMapMethod<String, dynamic>(
        'copyPdfsToLocal',
        {'sourcePath': selectedPath, 'destPath': pdfDirPath},
      );
      appLog('settings', 'iOS: native copy result=$result');

      if (result == null) {
        throw PlatformException(
          code: 'NULL_RESULT',
          message: 'Native channel returned null',
        );
      }

      final copied = result['copied'] as int? ?? 0;
      final total = result['total'] as int? ?? 0;
      appLog('settings', 'iOS: $copied/$total PDFs copied to $pdfDirPath');

      if (copied == 0 && total == 0) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No PDF files found in that folder')),
          );
        }
        return;
      }

      await notifier.setPdfFolderPath(pdfDirPath);
      appLog('settings', 'iOS: pdfFolderPath set to $pdfDirPath');

      if (context.mounted && copied > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$copied PDF(s) added')),
        );
      }
    } on PlatformException catch (e) {
      appLog('settings', 'iOS: native channel failed: ${e.message}');
      appLog('settings', 'iOS: falling back to multi-file picker');

      // Fallback — let the user pick individual PDF files.
      if (context.mounted) {
        await _pickPdfsIosFallback(context, notifier);
      }
    } on MissingPluginException {
      appLog('settings', 'iOS: native channel not available, using fallback');
      if (context.mounted) {
        await _pickPdfsIosFallback(context, notifier);
      }
    }
  }

  /// Fallback: pick individual PDF files (works without security-scoped
  /// directory access because file_picker handles per-file scope).
  Future<void> _pickPdfsIosFallback(
    BuildContext context,
    ConfigNotifier notifier,
  ) async {
    appLog('settings', 'iOS fallback: calling pickFiles(allowMultiple)…');
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      allowMultiple: true,
    );

    if (result == null || result.files.isEmpty) {
      appLog('settings', 'iOS fallback: user cancelled or no files');
      return;
    }

    final docsDir = await getApplicationDocumentsDirectory();
    final pdfDir = Directory('${docsDir.path}/pdfs');
    if (!pdfDir.existsSync()) pdfDir.createSync(recursive: true);
    appLog('settings', 'iOS fallback: local PDF dir = ${pdfDir.path}');

    var copied = 0;
    for (final pickedFile in result.files) {
      final sourcePath = pickedFile.path;
      if (sourcePath == null) continue;
      final name = pickedFile.name;
      final dest = '${pdfDir.path}/$name';
      try {
        await File(sourcePath).copy(dest);
        copied++;
        appLog('settings', 'iOS fallback: copied "$name" → $dest');
      } on Object catch (e) {
        appLog('settings', 'iOS fallback: failed to copy "$name": $e');
      }
    }

    appLog('settings', 'iOS fallback: $copied files copied to ${pdfDir.path}');
    await notifier.setPdfFolderPath(pdfDir.path);
    appLog('settings', 'iOS fallback: pdfFolderPath set to ${pdfDir.path}');

    if (context.mounted && copied > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$copied PDF(s) added')),
      );
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

  void _showLogViewer(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: SpeedyBoyTokens.shellBase,
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
                      const Text('Debug Logs',
                          style: SpeedyBoyTypography.title),
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
                                    content: Text('Logs copied to clipboard')),
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
                      style: SpeedyBoyTypography.caption.copyWith(
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
  Widget build(BuildContext context, WidgetRef ref) {
    final configAsync = ref.watch(configProvider);
    final config = configAsync.valueOrNull ?? const AppConfig();
    final notifier = ref.read(configProvider.notifier);
    final hasPremium = config.hasPremium;

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

          // ── Text Size (Premium only) ──
          if (hasPremium)
            NeumorphicCard(
              surface: SpeedyBoySurface.shell,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Text Size',
                    style: SpeedyBoyTypography.title,
                  ),
                  const SizedBox(height: 12),
                  FontSizeSlider(
                    value: config.fontScale,
                    onChanged: notifier.setFontScale,
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
                Text(
                  _isIos ? 'PDF Library' : 'PDF Folder',
                  style: SpeedyBoyTypography.title,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _isIos
                            ? (config.pdfFolderPath != null
                                ? 'PDFs stored locally'
                                : 'No PDFs added yet')
                            : (config.pdfFolderPath ?? 'No folder selected'),
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
                        foregroundColor: SpeedyBoyTokens.shellBase,
                      ),
                      onPressed: () => _pickFolder(context, notifier),
                      child: Text(
                        _isIos ? 'Import Folder' : 'Browse',
                        style: SpeedyBoyTypography.body.copyWith(
                          color: SpeedyBoyTokens.shellBase,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Anchor Color (Premium only) ──
          if (hasPremium)
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
                                    color: SpeedyBoyTokens.shellTextPrimary,
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

          // ── Reading Font (Premium only) ──
          if (hasPremium)
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

          // ── Upgrade to Premium (free users only) ──
          if (!hasPremium)
            NeumorphicCard(
              surface: SpeedyBoySurface.shell,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Unlock 3D Reading',
                    style: SpeedyBoyTypography.title,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Get the immersive 3D cube viewport, head-tracking '
                    'parallax, custom fonts, and reading range selection.',
                    style: SpeedyBoyTypography.body.copyWith(
                      color: SpeedyBoyTokens.shellTextSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: SpeedyBoyTokens.shellAccent,
                      foregroundColor: SpeedyBoyTokens.shellBase,
                    ),
                    onPressed: () =>
                        ref.read(purchaseServiceProvider).purchasePremium(),
                    child: Text(
                      'Upgrade',
                      style: SpeedyBoyTypography.body.copyWith(
                        color: SpeedyBoyTokens.shellBase,
                      ),
                    ),
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

          // ── Debug Logs ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Center(
              child: TextButton.icon(
                onPressed: () => _showLogViewer(context),
                icon: const Icon(Icons.bug_report,
                    size: 16, color: SpeedyBoyTokens.shellTextSecondary),
                label: Text(
                  'View Debug Logs',
                  style: SpeedyBoyTypography.caption.copyWith(
                    color: SpeedyBoyTokens.shellTextSecondary,
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
