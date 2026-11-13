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
import 'package:runthru/widgets/runthru_shell_widgets.dart';

/// Displays Google Drive connection state and supported Drive files.
class GoogleDriveSourcePanel extends ConsumerWidget {
  /// Creates the Google Drive source panel.
  const GoogleDriveSourcePanel({
    super.key,
    this.onOpenBrowserSetting,
    this.showDivider = false,
  });

  /// Opens the Settings screen focused on the full Drive browser setting.
  final VoidCallback? onOpenBrowserSetting;

  /// Whether to draw a hairline divider below the connection row.
  final bool showDivider;

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
          onConnect: () => ref.read(googleDriveAuthProvider.notifier).connect(),
          onOpenBrowserSetting:
              onOpenBrowserSetting ??
              () => context.go(
                '/?tab=3&focus=googleDriveBrowser&focusRequest=${DateTime.now().microsecondsSinceEpoch}',
              ),
          onDisconnect: () =>
              ref.read(googleDriveAuthProvider.notifier).disconnect(),
          showDivider: showDivider,
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

/// Shows an inline Drive file browser sheet and imports the chosen file.
///
/// Connects with `fullDriveBrowser` scope if not already connected, then
/// presents a searchable file list. On selection, triggers a Drive import
/// with [DriveImportOrigin.sources] so the caller's `ref.listen` can
/// navigate to the reader.
Future<void> showGoogleDriveFilePicker(
  BuildContext context,
  WidgetRef ref,
) async {
  final authState = ref.read(googleDriveAuthProvider);
  if (authState is! GoogleDriveAuthAuthenticated) {
    await ref
        .read(googleDriveAuthProvider.notifier)
        .connect(accessMode: GoogleDriveAccessMode.fullDriveBrowser);
    if (!context.mounted) return;
    if (ref.read(googleDriveAuthProvider) is! GoogleDriveAuthAuthenticated) {
      return;
    }
  }

  await ref
      .read(configProvider.notifier)
      .setGoogleDriveAccessMode(GoogleDriveAccessMode.fullDriveBrowser);
  if (!context.mounted) return;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: RunThruTokens.shellBase,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _DriveFilePickerSheet(
      onImport: (file) {
        ref
            .read(googleDriveImportProvider.notifier)
            .importFile(file, origin: DriveImportOrigin.sources);
      },
    ),
  );
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

class _ConnectionRow extends StatelessWidget {
  const _ConnectionRow({
    required this.authState,
    required this.accessMode,
    required this.onChooseFiles,
    required this.onConnect,
    required this.onOpenBrowserSetting,
    required this.onDisconnect,
    this.showDivider = false,
  });

  final GoogleDriveAuthState authState;
  final GoogleDriveAccessMode accessMode;
  final Future<void> Function() onChooseFiles;

  /// Signs in with the access mode saved in Settings.
  final Future<void> Function() onConnect;
  final VoidCallback onOpenBrowserSetting;
  final VoidCallback onDisconnect;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final isAuthenticated = authState is GoogleDriveAuthAuthenticated;
    final isLoading = authState is GoogleDriveAuthLoading;
    final accountLabel = isAuthenticated
        ? (authState as GoogleDriveAuthAuthenticated).user.label
        : null;

    final detail = switch (authState) {
      GoogleDriveAuthAuthenticated() =>
        accessMode == GoogleDriveAccessMode.fullDriveBrowser
            ? 'Full Drive browser enabled'
            : 'We only access files you choose',
      GoogleDriveAuthError(:final message) => message,
      _ => 'RunThru can only access files you choose',
    };

    final String? statusLabel;
    final RunThruStatusTone statusTone;
    if (isAuthenticated) {
      statusLabel = accountLabel;
      statusTone = RunThruStatusTone.ready;
    } else if (authState is GoogleDriveAuthError &&
        (authState as GoogleDriveAuthError).kind !=
            GoogleDriveFailureKind.userCancelled) {
      statusLabel = 'Needs attention';
      statusTone = RunThruStatusTone.warning;
    } else {
      statusLabel = 'Not connected';
      statusTone = RunThruStatusTone.neutral;
    }

    final Widget trailing;
    if (isAuthenticated) {
      trailing = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _MiniButton(
            icon: Icons.settings_outlined,
            tooltip: 'Google Drive settings',
            onPressed: onOpenBrowserSetting,
          ),
          _MiniButton(
            icon: Icons.logout_rounded,
            tooltip: 'Disconnect Google Drive',
            onPressed: onDisconnect,
          ),
        ],
      );
    } else {
      trailing = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _MiniButton(
            icon: Icons.settings_outlined,
            tooltip: 'Google Drive settings',
            onPressed: onOpenBrowserSetting,
          ),
          Opacity(
            opacity: isLoading ? 0.5 : 1.0,
            child: _ConnectPill(
              onTap: isLoading
                  ? null
                  : () {
                      // With "files you choose", connecting goes through
                      // the file picker. With the full Drive browser turned
                      // on in Settings there is nothing to pick first: sign
                      // in, and the browser appears in this panel. (This
                      // branch was missing, and the button did nothing.)
                      if (accessMode ==
                          GoogleDriveAccessMode.selectedFilesOnly) {
                        onChooseFiles();
                      } else {
                        onConnect();
                      }
                    },
            ),
          ),
        ],
      );
    }

    return Semantics(
      // Signed out, the Connect button says what there is to say.
      label: isAuthenticated ? 'Google Drive connected' : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Container(
          constraints: const BoxConstraints(minHeight: 60),
          decoration: showDivider
              ? const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: RunThruTokens.shellDivider,
                      width: 0.6,
                    ),
                  ),
                )
              : null,
          child: Padding(
            // 6 + the 48dp controls + 6 keeps the row at its 60dp height.
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: RunThruTokens.shellTealTint,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const GoogleDriveBrandIcon(size: 21),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Wrap, not Row: on narrow phones (390pt) and at
                      // larger text scales the status pill drops to its own
                      // line instead of overflowing.
                      Wrap(
                        spacing: 7,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            'Google Drive',
                            style: RunThruTypography.rowTitle.copyWith(
                              color: RunThruTokens.shellTextPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (statusLabel != null)
                            RunThruStatusPill(
                              label: statusLabel,
                              tone: statusTone,
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        detail,
                        style: RunThruTypography.metadata.copyWith(
                          color: RunThruTokens.shellTextSecondary,
                          fontSize: 11,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniButton extends StatelessWidget {
  const _MiniButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    // Drawn 34dp, tappable at 48dp, and announced once: the tooltip shows
    // on a long press, the label is what a screen reader says.
    return Tooltip(
      message: tooltip,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        label: tooltip,
        excludeSemantics: true,
        onTap: onPressed,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: SizedBox(
            width: RunThruA11y.minTapTarget,
            height: RunThruA11y.minTapTarget,
            child: Center(
              child: Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: RunThruDecorations.designerRaisedSmall(
                  borderRadius: 10,
                ),
                child: Icon(icon, size: 16, color: RunThruTokens.shellInkSoft),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The raised "Connect" pill: drawn 34dp high, tappable at 48dp.
class _ConnectPill extends StatelessWidget {
  const _ConnectPill({required this.onTap});

  /// Null while a sign-in is under way.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: 'Connect Google Drive',
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: RunThruA11y.minTapTarget,
            minHeight: RunThruA11y.minTapTarget,
          ),
          child: Center(
            widthFactor: 1,
            child: Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: RunThruDecorations.designerRaisedSmall(
                borderRadius: 999,
              ),
              child: Text(
                'Connect',
                style: RunThruTypography.caption.copyWith(
                  color: RunThruTokens.shellAccent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
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
      child: RunThruShellRow(
        title: file.name,
        metadata: _labelFor(file),
        icon: _iconFor(file),
        onTap: isImporting ? null : onTap,
        trailing: isImporting
            ? const RunThruStatusPill(
                label: 'Importing',
                tone: RunThruStatusTone.warning,
              )
            : null,
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

/// Inline Drive file browser shown as a modal bottom sheet.
class _DriveFilePickerSheet extends ConsumerStatefulWidget {
  const _DriveFilePickerSheet({required this.onImport});

  final void Function(GoogleDriveFile file) onImport;

  @override
  ConsumerState<_DriveFilePickerSheet> createState() =>
      _DriveFilePickerSheetState();
}

class _DriveFilePickerSheetState extends ConsumerState<_DriveFilePickerSheet> {
  late Future<List<GoogleDriveFile>> _filesFuture;
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _filesFuture = _fetchFiles();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<List<GoogleDriveFile>> _fetchFiles({String? query}) {
    return ref.read(googleDriveClientProvider).listDriveFiles(query: query);
  }

  void _search(String query) {
    setState(() {
      _query = query.trim();
      _filesFuture = _fetchFiles(query: _query.isEmpty ? null : _query);
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (context, scrollController) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                const GoogleDriveBrandIcon(size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Google Drive',
                    style: RunThruTypography.rowTitle.copyWith(
                      color: RunThruTokens.shellTextPrimary,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded, size: 20),
                  color: RunThruTokens.shellInkSoft,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search files',
                hintStyle: RunThruTypography.caption.copyWith(
                  color: RunThruTokens.shellTextSecondary,
                ),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  size: 20,
                  color: RunThruTokens.shellInkSoft,
                ),
                filled: true,
                fillColor: RunThruTokens.shellSandHi,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                isDense: true,
              ),
              style: RunThruTypography.caption.copyWith(
                color: RunThruTokens.shellTextPrimary,
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: _search,
              onChanged: (v) {
                if (v.isEmpty && _query.isNotEmpty) _search('');
              },
            ),
          ),
          Expanded(
            child: FutureBuilder<List<GoogleDriveFile>>(
              future: _filesFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                }
                if (snapshot.hasError) {
                  final error = snapshot.error;
                  final message = error is GoogleDriveException
                      ? error.message
                      : 'Could not load Drive files. Try again.';
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            message,
                            style: RunThruTypography.caption.copyWith(
                              color: RunThruTokens.shellTextSecondary,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: () => setState(() {
                              _filesFuture = _fetchFiles(
                                query: _query.isEmpty ? null : _query,
                              );
                            }),
                            child: Text(
                              'Retry',
                              style: RunThruTypography.caption.copyWith(
                                color: RunThruTokens.shellAccent,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                final files = snapshot.data ?? [];
                if (files.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        _query.isEmpty
                            ? 'No supported files found in Drive.'
                            : 'No results for "$_query".',
                        style: RunThruTypography.caption.copyWith(
                          color: RunThruTokens.shellTextSecondary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                return ListView.builder(
                  controller: scrollController,
                  itemCount: files.length,
                  itemBuilder: (context, index) {
                    final file = files[index];
                    return _DrivePickerFileRow(
                      file: file,
                      onTap: () {
                        Navigator.of(context).pop();
                        widget.onImport(file);
                      },
                    );
                  },
                );
              },
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
        ],
      ),
    );
  }
}

class _DrivePickerFileRow extends StatelessWidget {
  const _DrivePickerFileRow({required this.file, required this.onTap});

  final GoogleDriveFile file;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Import ${file.name} from Google Drive',
      child: RunThruShellRow(
        title: file.name,
        metadata: _labelFor(file),
        icon: _iconFor(file),
        onTap: onTap,
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
