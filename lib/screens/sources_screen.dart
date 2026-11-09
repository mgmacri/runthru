import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:runthru/core/clipboard_service.dart';
import 'package:runthru/design/design.dart';
import 'package:runthru/features/content/providers/instapaper_auth_provider.dart';
import 'package:runthru/features/content/providers/instapaper_bookmarks_provider.dart';
import 'package:runthru/features/content/providers/google_drive_auth_provider.dart';
import 'package:runthru/features/content/providers/google_drive_files_provider.dart';
import 'package:runthru/features/content/services/google_drive_client.dart';
import 'package:runthru/features/content/services/library_import.dart';
import 'package:runthru/features/content/widgets/brand_icons.dart';
import 'package:runthru/features/content/widgets/google_drive_source_panel.dart';
import 'package:runthru/features/content/widgets/instapaper_auth_tile.dart';
import 'package:runthru/services/folder_scanner.dart';
import 'package:runthru/store/library_source.dart';
import 'package:runthru/store/library_sources.dart';
import 'package:runthru/widgets/library_source_menu.dart';
import 'package:runthru/widgets/runthru_shell_widgets.dart';

/// Source-type filter for the dedicated Sources screen.
enum _SourcesFilter { all, folders, files, articles }

/// Dedicated screen for adding, connecting, and reviewing reading sources.
class SourcesScreen extends ConsumerStatefulWidget {
  /// Creates the dedicated Sources screen.
  const SourcesScreen({super.key, this.showBackButton = false});

  /// Whether to show an in-screen back button for pushed settings routes.
  final bool showBackButton;

  @override
  ConsumerState<SourcesScreen> createState() => _SourcesScreenState();
}

class _SourcesScreenState extends ConsumerState<SourcesScreen> {
  final ClipboardService _clipboardService = ClipboardService();
  _SourcesFilter _filter = _SourcesFilter.all;

  @override
  Widget build(BuildContext context) {
    final sources =
        ref.watch(librarySourcesProvider).valueOrNull ??
        const <LibrarySource>[];
    final userVisibleSources = sources.where(_isUserVisibleSource).toList();
    final folderSources = userVisibleSources
        .where((s) => s.kind == LibrarySourceKind.folder)
        .toList();
    final fileSources = userVisibleSources
        .where((s) => s.kind == LibrarySourceKind.file)
        .toList();
    final authState = ref.watch(instapaperAuthProvider);
    final isInstapaperConnected = authState is InstapaperAuthAuthenticated;
    // R-04: builds without OAuth dart-defines hide Drive entirely.
    final driveAvailable = ref.watch(googleDriveAvailableProvider);
    final driveAuthState = ref.watch(googleDriveAuthProvider);
    final isDriveConnected =
        driveAvailable && driveAuthState is GoogleDriveAuthAuthenticated;
    // Clipboard is always available, plus each user source and connected service.
    final sourceCount =
        1 +
        userVisibleSources.length +
        (isInstapaperConnected ? 1 : 0) +
        (isDriveConnected ? 1 : 0);

    ref.listen<ArticleImportState>(instapaperArticleImportProvider, (
      previous,
      next,
    ) {
      if (next is ArticleImportDone) {
        ref.read(instapaperArticleImportProvider.notifier).clear();
        context.push(
          '/read-instapaper',
          extra: {
            'document': next.document,
            'title': next.title,
            'bookmarkId': next.bookmarkId,
            'initialProgress': next.initialProgress,
          },
        );
      } else if (next is ArticleImportError) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(next.message)));
      }
    });

    ref.listen<GoogleDriveImportState>(googleDriveImportProvider, (
      previous,
      next,
    ) {
      if (next is GoogleDriveImportDone &&
          next.origin == DriveImportOrigin.sources) {
        ref.read(googleDriveImportProvider.notifier).clear();
        context.push(
          '/read-drive',
          extra: {
            'document': next.document,
            'identity': next.identity,
            'title': next.file.name,
            'fileId': next.file.id,
            'sourceId': next.identity.sourceId,
          },
        );
      } else if (next is GoogleDriveImportError &&
          next.origin == DriveImportOrigin.sources) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.message),
            action: next.kind == GoogleDriveFailureKind.permission
                ? SnackBarAction(
                    label: 'Grant access',
                    onPressed: () {
                      ref
                          .read(googleDriveFilesProvider.notifier)
                          .grantAccessAndRefresh();
                    },
                  )
                : null,
          ),
        );
      }
    });

    return Scaffold(
      backgroundColor: RunThruTokens.shellBase,
      body: SafeArea(
        child: Stack(
          children: [
            CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: _SourcesHeader(
                    sourceCount: sourceCount,
                    showBackButton: widget.showBackButton,
                  ),
                ),
                SliverToBoxAdapter(
                  child: _SourcesFilterRow(
                    selected: _filter,
                    onChanged: (filter) => setState(() => _filter = filter),
                  ),
                ),
                if (_filter == _SourcesFilter.all ||
                    _filter == _SourcesFilter.folders) ...[
                  const SliverToBoxAdapter(
                    child: _SourceSectionHeader(title: 'Folders'),
                  ),
                  for (int i = 0; i < folderSources.length; i++)
                    SliverToBoxAdapter(
                      child: _LibrarySourceRow(
                        source: folderSources[i],
                        onRemove: () => _handleRemoveSource(folderSources[i]),
                        showDivider: i < folderSources.length - 1,
                      ),
                    ),
                ],
                if (_filter == _SourcesFilter.all ||
                    _filter == _SourcesFilter.files) ...[
                  const SliverToBoxAdapter(
                    child: _SourceSectionHeader(title: 'Files'),
                  ),
                  for (final source in fileSources)
                    SliverToBoxAdapter(
                      child: _LibrarySourceRow(
                        source: source,
                        onRemove: () => _handleRemoveSource(source),
                        showDivider: true,
                      ),
                    ),
                  SliverToBoxAdapter(
                    child: _PlainSourceRow(
                      icon: Icons.content_paste,
                      title: 'Clipboard',
                      detail: 'Paste copied text into a temporary reader',
                      status: 'Ready',
                      statusColor: RunThruTokens.shellReady,
                      onTap: () => _handlePaste(context),
                      showDivider: true,
                    ),
                  ),
                  if (driveAvailable)
                    const SliverToBoxAdapter(child: GoogleDriveSourcePanel()),
                ],
                if (_filter == _SourcesFilter.all ||
                    _filter == _SourcesFilter.articles) ...[
                  const SliverToBoxAdapter(
                    child: _SourceSectionHeader(title: 'Articles'),
                  ),
                  const SliverToBoxAdapter(
                    child: InstapaperAuthTile(showDivider: true),
                  ),
                  const SliverToBoxAdapter(
                    child: _PlainSourceRow(
                      icon: Icons.mail_outline_rounded,
                      title: 'Substack',
                      detail: 'Newsletter article source',
                      status: 'Coming soon',
                      statusColor: RunThruTokens.shellTextSecondary,
                    ),
                  ),
                ],
                SliverToBoxAdapter(child: _EmptyFilterHint(filter: _filter)),
                const SliverPadding(padding: EdgeInsets.only(bottom: 96)),
              ],
            ),
            LibrarySourceMenu(
              actions: [
                LibrarySourceAction(
                  icon: Icons.content_paste,
                  label: 'Paste',
                  semanticsLabel: 'Paste from clipboard',
                  onTap: () => _handlePaste(context),
                ),
                LibrarySourceAction(
                  icon: Icons.insert_drive_file_outlined,
                  label: 'File',
                  semanticsLabel: 'Import files into library',
                  onTap: _handleImportFiles,
                ),
                LibrarySourceAction(
                  icon: Icons.folder_outlined,
                  label: 'Folder',
                  semanticsLabel: 'Import a folder into library',
                  onTap: _handleImportFolder,
                ),
                LibrarySourceAction(
                  icon: Icons.bookmark_outline,
                  iconWidget: const InstapaperBrandIcon(size: 20),
                  label: 'Instapaper',
                  semanticsLabel: 'Add from Instapaper',
                  onTap: () => _handleInstapaperAction(context),
                ),
                if (driveAvailable)
                  LibrarySourceAction(
                    icon: Icons.cloud_outlined,
                    iconWidget: const GoogleDriveBrandIcon(size: 20),
                    label: 'Drive',
                    semanticsLabel: 'Add from Google Drive',
                    onTap: () => _handleGoogleDriveAction(context),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  bool _isUserVisibleSource(LibrarySource source) {
    if (!source.ownsFiles) return !_isLegacyAppDataLocator(source.locator);
    return source.kind == LibrarySourceKind.folder &&
        (source.sourceKey?.isNotEmpty ?? false);
  }

  bool _isLegacyAppDataLocator(String locator) {
    final normalized = locator.replaceAll('\\', '/');
    return normalized == '/data/user/0/com.runthru.app/app_flutter' ||
        normalized.startsWith('/data/user/0/com.runthru.app/app_flutter/');
  }

  Future<void> _handleImportFiles() async {
    final sources = ref.read(librarySourcesProvider.notifier);
    await LibraryImport.pickFiles(context, sources);
    if (!mounted) return;
    ref.invalidate(pdfListProvider);
  }

  Future<void> _handleImportFolder() async {
    final sources = ref.read(librarySourcesProvider.notifier);
    await LibraryImport.pickFolder(context, sources);
    if (!mounted) return;
    ref.invalidate(pdfListProvider);
  }

  /// Removes a library source. Owned (imported) copies are deleted after
  /// confirmation; in-place references only drop from the scan list.
  Future<void> _handleRemoveSource(LibrarySource source) async {
    if (source.ownsFiles) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          backgroundColor: RunThruTokens.shellBase,
          title: Text(
            'Remove source?',
            style: RunThruTypography.title.copyWith(
              color: RunThruTokens.shellTextPrimary,
            ),
          ),
          content: Text(
            'The imported copies for "${source.displayName}" will be deleted '
            'to reclaim storage. Your original files are not affected.',
            style: RunThruTypography.body.copyWith(
              color: RunThruTokens.shellTextSecondary,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              child: Text(
                'Cancel',
                style: RunThruTypography.body.copyWith(
                  color: RunThruTokens.shellTextSecondary,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(true),
              child: Text(
                'Remove',
                style: RunThruTypography.body.copyWith(
                  color: RunThruTokens.shellError,
                ),
              ),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    try {
      await ref.read(librarySourcesProvider.notifier).remove(source.id);
    } on LibrarySourceRemovalException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not remove imported files. Check file permissions and try again.',
          ),
        ),
      );
      return;
    }
    if (!mounted) return;
    ref.invalidate(pdfListProvider);
  }

  void _handleInstapaperAction(BuildContext ctx) {
    final authState = ref.read(instapaperAuthProvider);
    final isAuthenticated = authState is InstapaperAuthAuthenticated;

    if (isAuthenticated) {
      ref.invalidate(instapaperBookmarksProvider);
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(
          content: Text('Syncing Instapaper...'),
          duration: Duration(seconds: 2),
        ),
      );
    } else {
      ctx.push('/settings/sources');
    }
  }

  Future<void> _handleGoogleDriveAction(BuildContext ctx) async {
    await showGoogleDriveFilePicker(ctx, ref);
  }

  Future<void> _handlePaste(BuildContext ctx) async {
    final doc = await _clipboardService.readFromClipboard();
    if (!ctx.mounted) return;

    if (doc == null) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(content: Text('Nothing to read - copy some text first')),
      );
      return;
    }

    final preview = doc.fullText.length > 100
        ? '${doc.fullText.substring(0, 100)}...'
        : doc.fullText;

    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: RunThruTokens.shellBase,
        title: Text(
          doc.title,
          style: RunThruTypography.title.copyWith(
            color: RunThruTokens.shellTextPrimary,
          ),
        ),
        content: Text(
          preview,
          style: RunThruTypography.body.copyWith(
            color: RunThruTokens.shellTextSecondary,
          ),
          maxLines: 5,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: Text(
              'Cancel',
              style: RunThruTypography.body.copyWith(
                color: RunThruTokens.shellTextSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: Text(
              'Start Reading',
              style: RunThruTypography.body.copyWith(
                color: RunThruTokens.shellAccent,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && ctx.mounted) {
      ctx.push('/read-clipboard', extra: doc);
    }
  }
}

class _SourcesHeader extends StatelessWidget {
  const _SourcesHeader({
    required this.sourceCount,
    required this.showBackButton,
  });

  final int sourceCount;
  final bool showBackButton;

  @override
  Widget build(BuildContext context) {
    return RunThruScreenHeader(
      title: 'Sources',
      subtitle:
          '$sourceCount ${sourceCount == 1 ? 'source' : 'sources'} connected',
      leading: showBackButton
          ? RunThruHeaderIconButton(
              icon: Icons.arrow_back_ios_new_rounded,
              tooltip: 'Back',
              onPressed: () => Navigator.of(context).pop(),
            )
          : null,
    );
  }
}

class _SourcesFilterRow extends StatelessWidget {
  const _SourcesFilterRow({required this.selected, required this.onChanged});

  final _SourcesFilter selected;
  final void Function(_SourcesFilter) onChanged;

  static const _labels = {
    _SourcesFilter.all: 'All',
    _SourcesFilter.folders: 'Folders',
    _SourcesFilter.files: 'Files',
    _SourcesFilter.articles: 'Articles',
  };

  @override
  Widget build(BuildContext context) {
    return RunThruSegmentedFilter<_SourcesFilter>(
      values: _SourcesFilter.values,
      selected: selected,
      labelFor: (filter) => _labels[filter]!,
      onChanged: onChanged,
    );
  }
}

class _SourceSectionHeader extends StatelessWidget {
  const _SourceSectionHeader({required this.title});

  final String title;

  static const _icons = {
    'Folders': Icons.folder_outlined,
    'Files': Icons.description_outlined,
    'Articles': Icons.article_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final icon = _icons[title] ?? Icons.circle_outlined;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: RunThruTokens.shellTealTint,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 15, color: RunThruTokens.shellAccent),
          ),
          const SizedBox(width: 10),
          Text(
            title,
            style: RunThruTypography.rowTitle.copyWith(
              color: RunThruTokens.shellTextPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// A configured library source with a remove control.
class _LibrarySourceRow extends StatelessWidget {
  const _LibrarySourceRow({
    required this.source,
    required this.onRemove,
    this.showDivider = false,
  });

  final LibrarySource source;
  final VoidCallback onRemove;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final isFolder = source.kind == LibrarySourceKind.folder;
    final detail = source.ownsFiles
        ? 'Imported copy · stored in app'
        : source.locator;
    return _SourceRow(
      icon: isFolder ? Icons.folder_outlined : Icons.insert_drive_file_outlined,
      title: source.displayName,
      detail: detail,
      showDivider: showDivider,
      trailing: Semantics(
        button: true,
        label: 'Remove ${source.displayName}',
        child: SizedBox(
          width: 44,
          height: 44,
          child: IconButton(
            icon: const Icon(Icons.close_rounded, size: 20),
            color: RunThruTokens.shellInkSoft,
            tooltip: 'Remove source',
            onPressed: onRemove,
          ),
        ),
      ),
    );
  }
}

class _PlainSourceRow extends StatelessWidget {
  const _PlainSourceRow({
    required this.icon,
    required this.title,
    required this.detail,
    required this.status,
    required this.statusColor,
    this.onTap,
    this.showDivider = false,
  });

  final IconData icon;
  final String title;
  final String detail;
  final String status;
  final Color statusColor;
  final VoidCallback? onTap;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final tone = statusColor == RunThruTokens.shellReady
        ? RunThruStatusTone.ready
        : RunThruStatusTone.neutral;
    final content = _SourceRow(
      icon: icon,
      title: title,
      detail: detail,
      showDivider: showDivider,
      trailing: RunThruStatusPill(label: status, tone: tone),
    );

    if (onTap == null) {
      return content;
    }

    return Semantics(
      button: true,
      label: title,
      child: GestureDetector(onTap: onTap, child: content),
    );
  }
}

/// Shared source row layout: flat icon tile + title/detail + trailing widget.
class _SourceRow extends StatelessWidget {
  const _SourceRow({
    required this.icon,
    required this.title,
    required this.detail,
    required this.trailing,
    this.showDivider = false,
  });

  final IconData icon;
  final String title;
  final String detail;
  final Widget trailing;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Padding(
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
          padding: const EdgeInsets.symmetric(vertical: 10),
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
                child: Icon(icon, size: 20, color: RunThruTokens.shellAccent),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: RunThruTypography.rowTitle.copyWith(
                        color: RunThruTokens.shellTextPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      style: RunThruTypography.metadata.copyWith(
                        color: RunThruTokens.shellTextSecondary,
                      ),
                      maxLines: 1,
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
    );
  }
}

class _EmptyFilterHint extends StatelessWidget {
  const _EmptyFilterHint({required this.filter});

  final _SourcesFilter filter;

  @override
  Widget build(BuildContext context) {
    final message = switch (filter) {
      _SourcesFilter.all => null,
      _SourcesFilter.folders => 'Use the + menu to add a folder source.',
      _SourcesFilter.files => 'Use the + menu to add files or paste text.',
      _SourcesFilter.articles =>
        'Instapaper is available now. Substack support can fit here later.',
    };

    if (message == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Text(
        message,
        style: RunThruTypography.caption.copyWith(
          color: RunThruTokens.shellTextSecondary,
        ),
      ),
    );
  }
}
