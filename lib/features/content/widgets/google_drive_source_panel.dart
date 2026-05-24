/// Google Drive source UI for the Sources screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runthru/design/design.dart';
import 'package:runthru/features/content/models/google_drive_file.dart';
import 'package:runthru/features/content/providers/google_drive_auth_provider.dart';
import 'package:runthru/features/content/providers/google_drive_files_provider.dart';
import 'package:runthru/widgets/neumorphic_card.dart';

/// Displays Google Drive connection state and supported Drive files.
class GoogleDriveSourcePanel extends ConsumerWidget {
  /// Creates the Google Drive source panel.
  const GoogleDriveSourcePanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(googleDriveAuthProvider);
    final filesState = ref.watch(googleDriveFilesProvider);
    final importState = ref.watch(googleDriveImportProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ConnectionRow(authState: authState),
        if (authState is GoogleDriveAuthAuthenticated)
          _FileList(
            state: filesState,
            importState: importState,
            onRefresh: () =>
                ref.read(googleDriveFilesProvider.notifier).refresh(),
            onSearch: () => _showDriveSearch(context, ref),
            onImport: (file) =>
                ref.read(googleDriveImportProvider.notifier).importFile(file),
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

class _ConnectionRow extends ConsumerWidget {
  const _ConnectionRow({required this.authState});

  final GoogleDriveAuthState authState;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = switch (authState) {
      GoogleDriveAuthChecking() => 'Checking...',
      GoogleDriveAuthUnauthenticated() => 'Not connected',
      GoogleDriveAuthLoading() => 'Connecting...',
      GoogleDriveAuthAuthenticated(:final user) => user.label,
      GoogleDriveAuthError() => 'Needs attention',
    };
    final detail = switch (authState) {
      GoogleDriveAuthAuthenticated() =>
        'Browse PDFs, EPUBs, Google Docs, text, and HTML',
      GoogleDriveAuthError(:final message) => message,
      _ => 'Read-only import from your Drive',
    };
    final ready = authState is GoogleDriveAuthAuthenticated;

    return _DriveCard(
      semanticsLabel: ready ? 'Google Drive connected' : 'Connect Google Drive',
      child: Row(
        children: [
          Icon(
            ready ? Icons.cloud_done_rounded : Icons.cloud_outlined,
            size: 22,
            color: ready ? RunThruTokens.shellReady : RunThruTokens.shellAccent,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Google Drive',
                  style: RunThruTypography.body.copyWith(
                    color: RunThruTokens.shellTextPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: RunThruTypography.caption.copyWith(
                    color: RunThruTokens.shellTextSecondary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            status,
            style: RunThruTypography.caption.copyWith(
              color: ready
                  ? RunThruTokens.shellReady
                  : RunThruTokens.shellTextSecondary,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.right,
          ),
          const SizedBox(width: 4),
          _ConnectionAction(authState: authState),
        ],
      ),
    );
  }
}

class _ConnectionAction extends ConsumerWidget {
  const _ConnectionAction({required this.authState});

  final GoogleDriveAuthState authState;

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
            : () => ref.read(googleDriveAuthProvider.notifier).connect(),
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
    required this.onSearch,
    required this.onImport,
  });

  final GoogleDriveFileListState state;
  final GoogleDriveImportState importState;
  final VoidCallback onRefresh;
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
            GoogleDriveFilesEmpty() => const _StatusText(
              'No supported Drive files found.',
            ),
            GoogleDriveFilesError(:final message) => _StatusText(message),
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

class _StatusText extends StatelessWidget {
  const _StatusText(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        message,
        style: RunThruTypography.caption.copyWith(
          color: RunThruTokens.shellTextSecondary,
        ),
      ),
    );
  }
}
