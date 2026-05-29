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
import 'package:runthru/widgets/neumorphic_card.dart';

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
    final driveAuthState = ref.watch(googleDriveAuthProvider);
    final isDriveConnected = driveAuthState is GoogleDriveAuthAuthenticated;
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
                  for (final source in folderSources)
                    SliverToBoxAdapter(
                      child: _LibrarySourceRow(
                        source: source,
                        onRemove: () => _handleRemoveSource(source),
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
                    ),
                  ),
                  const SliverToBoxAdapter(child: GoogleDriveSourcePanel()),
                ],
                if (_filter == _SourcesFilter.all ||
                    _filter == _SourcesFilter.articles) ...[
                  const SliverToBoxAdapter(
                    child: _SourceSectionHeader(title: 'Articles'),
                  ),
                  const SliverToBoxAdapter(child: InstapaperAuthTile()),
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
    await chooseGoogleDriveFilesForReading(ctx, ref);
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
    return Padding(
      padding: EdgeInsets.fromLTRB(showBackButton ? 8 : 20, 16, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (showBackButton) ...[
                Semantics(
                  label: 'Back',
                  button: true,
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded),
                      iconSize: 20,
                      color: RunThruTokens.shellTextPrimary,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
              ],
              const Expanded(
                child: Text('Sources', style: RunThruTypography.title),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              const Icon(
                Icons.add_link_rounded,
                size: 13,
                color: RunThruTokens.shellTextSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                '$sourceCount ${sourceCount == 1 ? 'source' : 'sources'} available',
                style: RunThruTypography.caption.copyWith(
                  color: RunThruTokens.shellTextSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
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
    final reduced = isReducedMotion(context);
    return SizedBox(
      height: 54,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
        scrollDirection: Axis.horizontal,
        children: _SourcesFilter.values.map((filter) {
          final isSelected = filter == selected;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Semantics(
              label: '${_labels[filter]} filter',
              selected: isSelected,
              button: true,
              child: GestureDetector(
                onTap: () => onChanged(filter),
                child: AnimatedContainer(
                  duration: reduced
                      ? Duration.zero
                      : const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 15,
                    vertical: 7,
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 38,
                  ),
                  decoration: isSelected
                      ? RunThruDecorations.insetDecoration(
                          RunThruSurface.shell,
                          size: RunThruShadowSize.small,
                          borderRadius: 999,
                        )
                      : RunThruDecorations.raisedDecoration(
                          RunThruSurface.shell,
                          size: RunThruShadowSize.small,
                          borderRadius: 999,
                        ),
                  child: Text(
                    _labels[filter]!,
                    style: RunThruTypography.caption.copyWith(
                      color: isSelected
                          ? RunThruTokens.shellTextPrimary
                          : RunThruTokens.shellTextSecondary,
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _SourceSectionHeader extends StatelessWidget {
  const _SourceSectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
      child: Text(
        title,
        style: RunThruTypography.caption.copyWith(
          color: RunThruTokens.shellTextSecondary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// A configured library source with a remove control.
class _LibrarySourceRow extends StatelessWidget {
  const _LibrarySourceRow({required this.source, required this.onRemove});

  final LibrarySource source;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final isFolder = source.kind == LibrarySourceKind.folder;
    final detail = source.ownsFiles
        ? 'Imported copy · stored in app'
        : source.locator;
    return NeumorphicCard(
      surface: RunThruSurface.shell,
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      borderRadius: 12,
      size: RunThruShadowSize.small,
      child: Row(
        children: [
          Icon(
            isFolder ? Icons.folder_outlined : Icons.insert_drive_file_outlined,
            size: 22,
            color: RunThruTokens.shellAccent,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  source.displayName,
                  style: RunThruTypography.body.copyWith(
                    color: RunThruTokens.shellTextPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
          const SizedBox(width: 8),
          Semantics(
            button: true,
            label: 'Remove ${source.displayName}',
            child: SizedBox(
              width: 44,
              height: 44,
              child: IconButton(
                icon: const Icon(Icons.close_rounded, size: 20),
                color: RunThruTokens.shellTextSecondary,
                tooltip: 'Remove source',
                onPressed: onRemove,
              ),
            ),
          ),
        ],
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
  });

  final IconData icon;
  final String title;
  final String detail;
  final String status;
  final Color statusColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = NeumorphicCard(
      surface: RunThruSurface.shell,
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      borderRadius: 12,
      size: RunThruShadowSize.small,
      child: Row(
        children: [
          Icon(icon, size: 22, color: RunThruTokens.shellAccent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
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
              color: statusColor,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.right,
          ),
        ],
      ),
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
