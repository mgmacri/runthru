/// Google Drive source UI for the Sources screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:runthru/design/design.dart';
import 'package:runthru/features/content/models/google_drive_file.dart';
import 'package:runthru/features/content/providers/google_drive_auth_provider.dart';
import 'package:runthru/features/content/providers/google_drive_files_provider.dart';
import 'package:runthru/features/content/providers/google_drive_picker_provider.dart';
import 'package:runthru/features/content/services/google_drive_client.dart';
import 'package:runthru/features/content/services/google_drive_picker.dart';
import 'package:runthru/features/content/widgets/brand_icons.dart';
import 'package:runthru/store/config.dart';
import 'package:runthru/store/models.dart';
import 'package:runthru/widgets/neumorphic_card.dart';

/// Displays Google Drive connection state and supported Drive files.
class GoogleDriveSourcePanel extends ConsumerWidget {
  /// Creates the Google Drive source panel.
  const GoogleDriveSourcePanel({super.key, this.onOpenBrowserSetting});

  /// Opens the Settings screen focused on the full Drive browser setting.
  final VoidCallback? onOpenBrowserSetting;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(googleDriveAuthProvider);
    final filesState = ref.watch(googleDriveFilesProvider);
    final importState = ref.watch(googleDriveImportProvider);
    final accessMode =
        ref.watch(configProvider).valueOrNull?.googleDriveAccessMode ??
        GoogleDriveAccessMode.selectedFilesOnly;
    final isFullBrowser = accessMode == GoogleDriveAccessMode.fullDriveBrowser;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ConnectionRow(
          authState: authState,
          accessMode: accessMode,
          onChooseFiles: () => chooseGoogleDriveFilesForReading(context, ref),
          onOpenBrowserSetting:
              onOpenBrowserSetting ??
              () => context.go(
                '/?tab=3&focus=googleDriveBrowser&focusRequest=${DateTime.now().microsecondsSinceEpoch}',
              ),
        ),
        if (authState is GoogleDriveAuthAuthenticated && isFullBrowser)
          _FileList(
            state: filesState,
            importState: importState,
            onRefresh: () =>
                ref.read(googleDriveFilesProvider.notifier).refresh(),
            onGrantAccess: () => ref
                .read(googleDriveFilesProvider.notifier)
                .grantAccessAndRefresh(),
            onSearch: () => _showDriveSearch(context, ref),
            onImport: (file) => ref
                .read(googleDriveImportProvider.notifier)
                .importFile(file, origin: DriveImportOrigin.sources),
          ),
      ],
    );
  }

  Future<void> _showDriveSearch(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final query = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: RunThruTokens.shellBase,
        title: Text(
          'Search Drive',
          style: RunThruTypography.title.copyWith(
            color: RunThruTokens.shellTextPrimary,
          ),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'File name',
            labelStyle: RunThruTypography.caption.copyWith(
              color: RunThruTokens.shellTextSecondary,
            ),
          ),
          style: RunThruTypography.body.copyWith(
            color: RunThruTokens.shellTextPrimary,
          ),
          textInputAction: TextInputAction.search,
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(
              'Cancel',
              style: RunThruTypography.body.copyWith(
                color: RunThruTokens.shellTextSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: Text(
              'Search',
              style: RunThruTypography.body.copyWith(
                color: RunThruTokens.shellAccent,
              ),
            ),
          ),
        ],
      ),
    );
    controller.dispose();
    if (query == null) return;
    await ref.read(googleDriveFilesProvider.notifier).refresh(query: query);
  }
}

/// Opens the selected-files Google Drive picker and imports chosen files.
Future<void> chooseGoogleDriveFilesForReading(
  BuildContext context,
  WidgetRef ref,
) async {
  final authenticated = await _ensureSelectedFileAccess(context, ref);
  if (!authenticated) return;
  if (!context.mounted) return;

  final pickedFiles = await _pickDriveFiles(context, ref);
  if (pickedFiles == null || pickedFiles.isEmpty) return;

  final invalidMessage = _selectedFileValidationMessage(pickedFiles);
  if (invalidMessage != null) {
    if (!context.mounted) return;
    _showGoogleDriveSnack(context, invalidMessage);
    return;
  }

  await ref
      .read(googleDriveImportProvider.notifier)
      .importPickedDriveFileIds(
        pickedFiles.map((file) => file.id).toList(growable: false),
        origin: DriveImportOrigin.sources,
      );
}

Future<bool> _ensureSelectedFileAccess(
  BuildContext context,
  WidgetRef ref,
) async {
  final authState = ref.read(googleDriveAuthProvider);
  if (authState is! GoogleDriveAuthAuthenticated) {
    await ref
        .read(googleDriveAuthProvider.notifier)
        .connect(accessMode: GoogleDriveAccessMode.selectedFilesOnly);
    if (!context.mounted) return false;
    if (ref.read(googleDriveAuthProvider) is! GoogleDriveAuthAuthenticated) {
      return false;
    }
  }
  return true;
}

Future<List<GoogleDrivePickedFile>?> _pickDriveFiles(
  BuildContext context,
  WidgetRef ref,
) async {
  try {
    return await ref
        .read(googleDrivePickerProvider)
        .pickFiles(
          allowMultiple: true,
          mimeTypes: supportedDriveMimeTypes.toList(growable: false),
        );
  } on GoogleDrivePickerUnavailableException catch (e) {
    if (context.mounted) _showGoogleDriveSnack(context, e.message);
    return null;
  } on Object {
    if (context.mounted) {
      _showGoogleDriveSnack(
        context,
        'Could not open Google Drive file picker. Try again.',
      );
    }
    return null;
  }
}

String? _selectedFileValidationMessage(List<GoogleDrivePickedFile> files) {
  for (final file in files) {
    if (file.id.trim().isEmpty) {
      return 'Could not read the selected Drive file.';
    }
    if (file.isFolder) {
      return 'Folders are not supported.';
    }
    if (file.hasUnsupportedMimeType) {
      return 'That Drive file type is not supported.';
    }
  }
  return null;
}

void _showGoogleDriveSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

class _ConnectionRow extends ConsumerWidget {
  const _ConnectionRow({
    required this.authState,
    required this.accessMode,
    required this.onChooseFiles,
    required this.onOpenBrowserSetting,
  });

  final GoogleDriveAuthState authState;
  final GoogleDriveAccessMode accessMode;
  final Future<void> Function() onChooseFiles;
  final VoidCallback onOpenBrowserSetting;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = _statusFor(authState);
    final detail = switch (authState) {
      GoogleDriveAuthAuthenticated() =>
        accessMode == GoogleDriveAccessMode.fullDriveBrowser
            ? 'Full Drive browser enabled'
            : 'RunThru can only access files you choose',
      GoogleDriveAuthError(:final message) => message,
      _ => 'RunThru can only access files you choose',
    };
    final ready = authState is GoogleDriveAuthAuthenticated;

    return _DriveCard(
      semanticsLabel: ready ? 'Google Drive connected' : 'Connect Google Drive',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(
            width: 44,
            height: 44,
            child: Center(child: GoogleDriveBrandIcon(size: 28)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Google Drive',
                        style: RunThruTypography.body.copyWith(
                          color: RunThruTokens.shellTextPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _DriveStatusBadge(label: status, ready: ready),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  detail,
                  style: RunThruTypography.caption.copyWith(
                    color: RunThruTokens.shellTextSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 48,
            height: 48,
            child: IconButton(
              tooltip: 'Google Drive settings',
              onPressed: onOpenBrowserSetting,
              icon: const Icon(Icons.settings_outlined, size: 20),
              color: RunThruTokens.shellTextSecondary,
            ),
          ),
          _ConnectionAction(
            authState: authState,
            accessMode: accessMode,
            onChooseFiles: onChooseFiles,
          ),
        ],
      ),
    );
  }

  String _statusFor(GoogleDriveAuthState authState) => switch (authState) {
    GoogleDriveAuthChecking() => 'Checking',
    GoogleDriveAuthUnauthenticated() => 'Not connected',
    GoogleDriveAuthLoading() => 'Connecting',
    GoogleDriveAuthAuthenticated(:final user) => user.label,
    GoogleDriveAuthError(kind: GoogleDriveFailureKind.userCancelled) =>
      'Not connected',
    GoogleDriveAuthError() => 'Needs attention',
  };
}

class _DriveStatusBadge extends StatelessWidget {
  const _DriveStatusBadge({required this.label, required this.ready});

  final String label;
  final bool ready;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 112),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: (ready ? RunThruTokens.shellReady : RunThruTokens.shellAccent)
              .withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          child: Text(
            label,
            style: RunThruTypography.caption.copyWith(
              color: ready
                  ? RunThruTokens.shellReady
                  : RunThruTokens.shellTextSecondary,
              fontWeight: FontWeight.w700,
              height: 1.1,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

class _ConnectionAction extends ConsumerWidget {
  const _ConnectionAction({
    required this.authState,
    required this.accessMode,
    required this.onChooseFiles,
  });

  final GoogleDriveAuthState authState;
  final GoogleDriveAccessMode accessMode;
  final Future<void> Function() onChooseFiles;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (authState is GoogleDriveAuthAuthenticated) {
      return SizedBox(
        width: 48,
        height: 48,
        child: IconButton(
          tooltip: 'Disconnect Google Drive',
          onPressed: () =>
              ref.read(googleDriveAuthProvider.notifier).disconnect(),
          icon: const Icon(Icons.logout_rounded, size: 20),
          color: RunThruTokens.shellTextSecondary,
        ),
      );
    }
    return SizedBox(
      height: 44,
      child: TextButton(
        onPressed: authState is GoogleDriveAuthLoading
            ? null
            : () {
                if (accessMode == GoogleDriveAccessMode.selectedFilesOnly) {
                  onChooseFiles();
                  return;
                }
                ref.read(googleDriveAuthProvider.notifier).connect();
              },
        child: Text(
          'Connect',
          style: RunThruTypography.caption.copyWith(
            color: RunThruTokens.shellAccent,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _FileList extends StatelessWidget {
  const _FileList({
    required this.state,
    required this.importState,
    required this.onRefresh,
    required this.onGrantAccess,
    required this.onSearch,
    required this.onImport,
  });

  final GoogleDriveFileListState state;
  final GoogleDriveImportState importState;
  final VoidCallback onRefresh;
  final Future<void> Function() onGrantAccess;
  final VoidCallback onSearch;
  final ValueChanged<GoogleDriveFile> onImport;

  @override
  Widget build(BuildContext context) {
    final files = state is GoogleDriveFilesLoaded
        ? (state as GoogleDriveFilesLoaded).files
        : const <GoogleDriveFile>[];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Drive files',
                  style: RunThruTypography.caption.copyWith(
                    color: RunThruTokens.shellTextSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Search Google Drive',
                onPressed: onSearch,
                icon: const Icon(Icons.search_rounded, size: 20),
                color: RunThruTokens.shellTextSecondary,
              ),
              IconButton(
                tooltip: 'Refresh Google Drive files',
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh_rounded, size: 20),
                color: RunThruTokens.shellTextSecondary,
              ),
            ],
          ),
          switch (state) {
            GoogleDriveFilesLoading() => const _StatusText('Loading Drive...'),
            GoogleDriveFilesNotConnected() => const SizedBox.shrink(),
            GoogleDriveFilesSelectedFilesOnly() => const SizedBox.shrink(),
            GoogleDriveFilesEmpty() => const _StatusText(
              'No supported Drive files found.',
            ),
            GoogleDriveFilesError(:final message, :final kind) =>
              kind == GoogleDriveFailureKind.permission
                  ? _StatusAction(
                      message: message,
                      actionLabel: 'Grant access',
                      onPressed: onGrantAccess,
                    )
                  : _StatusText(message),
            GoogleDriveFilesLoaded(:final refreshing) => Column(
              children: [
                if (refreshing) const _StatusText('Refreshing Drive...'),
                for (final file in files.take(8))
                  _DriveFileRow(
                    file: file,
                    importState: importState,
                    onTap: () => onImport(file),
                  ),
              ],
            ),
          },
        ],
      ),
    );
  }
}

class _DriveFileRow extends StatelessWidget {
  const _DriveFileRow({
    required this.file,
    required this.importState,
    required this.onTap,
  });

  final GoogleDriveFile file;
  final GoogleDriveImportState importState;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isImporting =
        importState is GoogleDriveImportLoading &&
        (importState as GoogleDriveImportLoading).file.id == file.id;
    return Semantics(
      button: true,
      label: 'Import ${file.name} from Google Drive',
      child: GestureDetector(
        onTap: isImporting ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Icon(_iconFor(file), size: 20, color: RunThruTokens.shellAccent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  file.name,
                  style: RunThruTypography.caption.copyWith(
                    color: RunThruTokens.shellTextPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                isImporting ? 'Importing...' : _labelFor(file),
                style: RunThruTypography.caption.copyWith(
                  color: isImporting
                      ? RunThruTokens.stageProgress
                      : RunThruTokens.shellTextSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static IconData _iconFor(GoogleDriveFile file) => switch (file.mimeType) {
    googleDocsMimeType => Icons.description_outlined,
    pdfMimeType => Icons.picture_as_pdf_outlined,
    epubMimeType => Icons.menu_book_outlined,
    htmlMimeType => Icons.code_rounded,
    _ => Icons.text_snippet_outlined,
  };

  static String _labelFor(GoogleDriveFile file) => switch (file.mimeType) {
    googleDocsMimeType => 'Google Doc',
    pdfMimeType => 'PDF',
    epubMimeType => 'EPUB',
    htmlMimeType => 'HTML',
    _ => 'Text',
  };
}

class _DriveCard extends StatelessWidget {
  const _DriveCard({required this.child, required this.semanticsLabel});

  final Widget child;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticsLabel,
      child: NeumorphicCard(
        surface: RunThruSurface.shell,
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        borderRadius: 12,
        size: RunThruShadowSize.small,
        child: child,
      ),
    );
  }
}

class _StatusAction extends StatelessWidget {
  const _StatusAction({
    required this.message,
    required this.actionLabel,
    required this.onPressed,
  });

  final String message;
  final String actionLabel;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: _StatusText(message, bottomPadding: 0)),
          const SizedBox(width: 8),
          SizedBox(
            height: 44,
            child: TextButton(
              onPressed: onPressed,
              child: Text(
                actionLabel,
                style: RunThruTypography.caption.copyWith(
                  color: RunThruTokens.shellAccent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusText extends StatelessWidget {
  const _StatusText(this.message, {this.bottomPadding = 10});

  final String message;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: Text(
        message,
        style: RunThruTypography.caption.copyWith(
          color: RunThruTokens.shellTextSecondary,
        ),
      ),
    );
  }
}
