import 'dart:io' show Directory, File, Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:runthru/core/logger.dart';
import 'package:runthru/design/design.dart';
import 'package:runthru/store/library_sources.dart';

/// Shared folder- and file-import flows for the library.
///
/// Centralises the platform-specific picker logic (Android SAF, iOS
/// security-scoped access, desktop directory picking, and multi-file
/// fallbacks) so both the Settings screen and the Library `+` menu can add
/// sources without duplicating native-channel plumbing.
///
/// Sources are **added** to [LibrarySourcesNotifier] (never replacing prior
/// ones). Real OS paths (desktop, Android ≤12) are referenced **in place** —
/// zero copy. Where the platform gives no durable path (Android 13+ SAF, iOS),
/// files are copied into a per-source app directory tagged `ownsFiles` so the
/// copy is reclaimed when the source is removed. Content stays on-device.
class LibraryImport {
  LibraryImport._();

  /// Extensions the folder scanner can display in the Books grid.
  static const List<String> supportedExtensions = ['pdf', 'epub'];

  /// Returns true when [path] points at a book type RunThru can import.
  static bool isSupportedBookPath(String path) {
    final lower = path.toLowerCase();
    return supportedExtensions.any(
      (extension) => lower.endsWith('.$extension'),
    );
  }

  /// Returns a non-existing destination file in [dir] for [fileName].
  ///
  /// Existing files are preserved by suffixing later collisions as
  /// `book (2).pdf`, `book (3).pdf`, and so on.
  static File uniqueDestinationFile(Directory dir, String fileName) {
    final baseName = _basename(fileName);
    var candidate = File('${dir.path}/$baseName');
    if (!candidate.existsSync()) return candidate;

    final dot = baseName.lastIndexOf('.');
    final stem = dot > 0 ? baseName.substring(0, dot) : baseName;
    final extension = dot > 0 ? baseName.substring(dot) : '';
    var suffix = 2;
    do {
      candidate = File('${dir.path}/$stem ($suffix)$extension');
      suffix++;
    } while (candidate.existsSync());
    return candidate;
  }

  static bool get _isIos {
    if (kIsWeb) return false;
    return Platform.isIOS;
  }

  static bool get _isMobile {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  /// Picks a folder and adds it as a library source.
  ///
  /// Desktop / Android ≤12 reference the folder in place; Android 13+ and iOS
  /// copy the folder's books into an app-managed per-source directory.
  static Future<void> pickFolder(
    BuildContext context,
    LibrarySourcesNotifier sources,
  ) async {
    try {
      appLog('import', 'pickFolder — isIos=$_isIos');

      if (_isIos) {
        await _importIosFolder(context, sources);
        return;
      }

      if (!kIsWeb && Platform.isAndroid) {
        final androidInfo = await DeviceInfoPlugin().androidInfo;
        final sdkInt = androidInfo.version.sdkInt;
        appLog('import', 'Android SDK=$sdkInt');

        if (sdkInt >= 33) {
          // Android 13+: SAF + native copy to an app-managed per-source dir.
          if (context.mounted) {
            await _importAndroidSafFolder(context, sources);
          }
          return;
        }

        // Android 12 and below: request legacy storage permission.
        if (!context.mounted) return;
        if (!await _ensureStoragePermission(context)) return;
      } else if (!kIsWeb) {
        // Desktop: check storage permission as before.
        if (!await _ensureStoragePermission(context)) return;
      }

      appLog('import', 'calling FilePicker.getDirectoryPath()…');
      final result = await FilePicker.platform.getDirectoryPath();
      appLog('import', 'FilePicker result=$result');
      if (result != null) {
        // Real OS path — reference it in place (no copy).
        await sources.addFolder(result, ownsFiles: false);
      }
    } on Object catch (e) {
      appLog('import', 'Folder pick failed: $e');
      if (!context.mounted) return;
      _showError(context, 'Could not open file picker: $e');
    }
  }

  /// Picks one or more files and adds them to the library.
  ///
  /// Desktop references each file in place; mobile copies the selection into a
  /// single app-managed per-source directory (so removal reclaims the copies).
  static Future<void> pickFiles(
    BuildContext context,
    LibrarySourcesNotifier sources,
  ) async {
    try {
      appLog('import', 'pickFiles — calling pickFiles(allowMultiple)…');
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: supportedExtensions,
        allowMultiple: true,
      );

      if (result == null || result.files.isEmpty) {
        appLog('import', 'pickFiles — user cancelled or no files');
        return;
      }

      if (!_isMobile) {
        // Desktop: file_picker returns real paths — reference in place.
        for (final picked in result.files) {
          final path = picked.path;
          if (path != null) {
            await sources.addFile(path, ownsFiles: false);
          }
        }
        return;
      }

      // Mobile: copy the selection into one app-managed source directory.
      if (context.mounted) {
        await _copyFilesIntoOwnedSource(context, sources, result.files);
      }
    } on Object catch (e) {
      appLog('import', 'pickFiles failed: $e');
      if (!context.mounted) return;
      _showError(context, 'Could not open file picker: $e');
    }
  }

  /// Android 13+ (API 33+): native SAF picker copies books into a per-source
  /// app directory (URI permission persistence + copy happen Kotlin-side).
  static Future<void> _importAndroidSafFolder(
    BuildContext context,
    LibrarySourcesNotifier sources,
  ) async {
    final dir = await _freshSourceDir();
    appLog('import', 'Android SAF: dest=${dir.path}');

    try {
      const channel = MethodChannel('com.runthru/android_file_access');
      final result = await channel.invokeMapMethod<String, dynamic>(
        'pickAndCopyPdfs',
        {'destPath': dir.path},
      );
      appLog('import', 'Android SAF: native result=$result');

      if (result == null) {
        throw PlatformException(
          code: 'NULL_RESULT',
          message: 'Native channel returned null',
        );
      }

      if (result['cancelled'] as bool? ?? false) {
        appLog('import', 'Android SAF: user cancelled');
        await _deleteDirQuietly(dir);
        return;
      }

      final copied = result['copied'] as int? ?? 0;
      if (copied == 0) {
        await _deleteDirQuietly(dir);
        if (!context.mounted) return;
        _showSnack(context, 'No supported books found in that folder');
        return;
      }

      final displayName = result['displayName'] as String?;
      final treeUri = result['treeUri'] as String?;
      final added = await sources.addFolder(
        dir.path,
        ownsFiles: true,
        displayName: displayName,
        sourceKey: treeUri == null || treeUri.isEmpty
            ? null
            : 'android-tree:$treeUri',
      );
      if (!added) {
        await _deleteDirQuietly(dir);
        if (!context.mounted) return;
        _showSnack(context, 'That folder is already in Sources');
        return;
      }
      if (!context.mounted) return;
      _showSnack(context, '$copied book(s) added');
    } on PlatformException catch (e) {
      appLog('import', 'Android SAF: native channel failed: ${e.message}');
      await _deleteDirQuietly(dir);
      if (context.mounted) await pickFiles(context, sources);
    } on MissingPluginException {
      appLog('import', 'Android SAF: channel unavailable, using fallback');
      await _deleteDirQuietly(dir);
      if (context.mounted) await pickFiles(context, sources);
    }
  }

  /// iOS: pick a folder, copy its books into a per-source app directory via the
  /// native security-scoped channel. Falls back to multi-file picking.
  static Future<void> _importIosFolder(
    BuildContext context,
    LibrarySourcesNotifier sources,
  ) async {
    appLog('import', 'iOS: calling getDirectoryPath()…');
    final selectedPath = await FilePicker.platform.getDirectoryPath();
    if (selectedPath == null) {
      appLog('import', 'iOS: user cancelled');
      return;
    }

    final dir = await _freshSourceDir();
    try {
      const channel = MethodChannel('com.runthru/ios_file_access');
      final result = await channel.invokeMapMethod<String, dynamic>(
        'copyPdfsToLocal',
        {'sourcePath': selectedPath, 'destPath': dir.path},
      );
      appLog('import', 'iOS: native copy result=$result');

      if (result == null) {
        throw PlatformException(
          code: 'NULL_RESULT',
          message: 'Native channel returned null',
        );
      }

      final copied = result['copied'] as int? ?? 0;
      if (copied == 0) {
        await _deleteDirQuietly(dir);
        if (!context.mounted) return;
        _showSnack(context, 'No supported books found in that folder');
        return;
      }

      final added = await sources.addFolder(
        dir.path,
        ownsFiles: true,
        displayName: _basename(selectedPath),
        sourceKey: 'ios-folder:$selectedPath',
      );
      if (!added) {
        await _deleteDirQuietly(dir);
        if (!context.mounted) return;
        _showSnack(context, 'That folder is already in Sources');
        return;
      }
      if (!context.mounted) return;
      _showSnack(context, '$copied book(s) added');
    } on PlatformException catch (e) {
      appLog('import', 'iOS: native channel failed: ${e.message}');
      await _deleteDirQuietly(dir);
      if (context.mounted) await pickFiles(context, sources);
    } on MissingPluginException {
      appLog('import', 'iOS: native channel unavailable, using fallback');
      await _deleteDirQuietly(dir);
      if (context.mounted) await pickFiles(context, sources);
    }
  }

  /// Copies picked files into one fresh app-managed directory and adds it as a
  /// single owned folder source.
  static Future<void> _copyFilesIntoOwnedSource(
    BuildContext context,
    LibrarySourcesNotifier sources,
    List<PlatformFile> files,
  ) async {
    final dir = await _freshSourceDir();
    var copied = 0;
    for (final picked in files) {
      final sourcePath = picked.path;
      if (sourcePath == null) continue;
      try {
        if (!isSupportedBookPath(picked.name)) continue;
        final destination = uniqueDestinationFile(dir, picked.name);
        await File(sourcePath).copy(destination.path);
        copied++;
      } on Object catch (e) {
        appLog('import', 'failed to copy "${picked.name}": $e');
      }
    }

    if (copied == 0) {
      await _deleteDirQuietly(dir);
      if (!context.mounted) return;
      _showSnack(context, 'Could not import the selected files');
      return;
    }

    await sources.addFolder(
      dir.path,
      ownsFiles: true,
      displayName: 'Imported files',
    );
    if (!context.mounted) return;
    _showSnack(context, '$copied file(s) added');
  }

  /// Creates a unique app-managed directory under `<appDocs>/library/`.
  static Future<Directory> _freshSourceDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final id = '${DateTime.now().microsecondsSinceEpoch}';
    final dir = Directory('${docs.path}/library/$id');
    await dir.create(recursive: true);
    return dir;
  }

  static Future<void> _deleteDirQuietly(Directory dir) async {
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
    } on Object catch (e) {
      appLog('import', 'cleanup failed for ${dir.path}: $e');
    }
  }

  static Future<bool> _ensureStoragePermission(BuildContext context) async {
    final status = await Permission.storage.status;
    appLog('import', 'storage permission status=$status');
    if (status.isDenied) {
      final result = await Permission.storage.request();
      appLog('import', 'storage permission request result=$result');
      if (result.isPermanentlyDenied && context.mounted) {
        _showPermissionDeniedDialog(context);
        return false;
      }
      if (!result.isGranted) return false;
    }
    return true;
  }

  static void _showSnack(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  static void _showError(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: RunThruTokens.shellError,
      ),
    );
  }

  static void _showPermissionDeniedDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'Permission Required',
          style: RunThruTypography.title,
        ),
        content: const Text(
          'RunThru needs file access permission to scan '
          'your PDF folders. Please enable it in Settings.',
          style: RunThruTypography.body,
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

  static String _basename(String path) {
    final normalized = path.replaceAll('\\', '/');
    final idx = normalized.lastIndexOf('/');
    return idx >= 0 ? normalized.substring(idx + 1) : normalized;
  }
}
