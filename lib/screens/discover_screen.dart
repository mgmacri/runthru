import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runthru/core/logger.dart';
import 'package:runthru/design/design.dart';
import 'package:runthru/services/opds_service.dart';

/// Discover screen — browse and download Project Gutenberg books.
class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key});

  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  String? _query;
  int _page = 1;

  /// Track which entry ID is currently downloading.
  String? _downloadingId;

  /// User-facing message after a download completes or fails.
  String? _statusMessage;
  bool _statusIsError = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      setState(() {
        _query = value.trim().isEmpty ? null : value.trim();
        _page = 1;
      });
    });
  }

  Future<void> _download(OpdsEntry entry) async {
    if (_downloadingId != null) return;

    setState(() {
      _downloadingId = entry.id;
      _statusMessage = null;
    });

    try {
      final service = ref.read(opdsServiceProvider);
      appLog(
        'discover',
        'download tap title="${entry.title}" linkCount=${entry.links.length}',
      );
      await service.downloadBook(entry);

      if (!mounted) return;
      setState(() {
        _statusMessage = 'Added "${entry.title}" to library';
        _statusIsError = false;
      });
      appLog('discover', 'download success title="${entry.title}"');
    } on Exception catch (e) {
      if (!mounted) return;
      appLog('discover', 'download exception title="${entry.title}" error=$e');
      setState(() {
        _statusMessage = 'Download failed: $e';
        _statusIsError = true;
      });
    } finally {
      if (mounted) {
        setState(() => _downloadingId = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(
      opdsCatalogProvider((query: _query, page: _page)),
    );

    return Scaffold(
      backgroundColor: RunThruTokens.shellBase,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 16, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Discover Books',
                      style: RunThruTypography.display,
                    ),
                  ),
                ],
              ),
            ),

            // ── Search bar ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Container(
                decoration: RunThruDecorations.insetDecoration(
                  RunThruSurface.shell,
                  size: RunThruShadowSize.small,
                  borderRadius: 12,
                ),
                child: TextField(
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  style: RunThruTypography.body,
                  decoration: InputDecoration(
                    hintText: 'Search public domain books…',
                    hintStyle: RunThruTypography.body.copyWith(
                      color: RunThruTokens.shellTextSecondary,
                    ),
                    prefixIcon: const Icon(
                      Icons.search,
                      color: RunThruTokens.shellTextSecondary,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                  ),
                ),
              ),
            ),

            // ── Status message ──
            if (_statusMessage != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 4,
                ),
                child: Text(
                  _statusMessage!,
                  style: RunThruTypography.caption.copyWith(
                    color: _statusIsError
                        ? RunThruTokens.shellError
                        : RunThruTokens.shellReady,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),

            // ── Results ──
            Expanded(
              child: catalog.when(
                data: _buildResults,
                loading: () => Center(
                  child: Text(
                    'Searching…',
                    style: RunThruTypography.body.copyWith(
                      color: RunThruTokens.shellTextSecondary,
                    ),
                  ),
                ),
                error: (error, _) => _buildError(error),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResults(OpdsCatalog catalog) {
    if (catalog.entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            _query != null
                ? 'No results for "$_query".'
                : 'Browse Project Gutenberg\'s catalog.\nType a title or author above.',
            style: RunThruTypography.body.copyWith(
              color: RunThruTokens.shellTextSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 0.62,
            ),
            itemCount: catalog.entries.length,
            itemBuilder: (context, index) => _BookCard(
              entry: catalog.entries[index],
              isDownloading: _downloadingId == catalog.entries[index].id,
              onDownload: () => _download(catalog.entries[index]),
            ),
          ),
        ),

        // ── Pagination ──
        if (catalog.nextUrl != null || _page > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_page > 1)
                  TextButton(
                    onPressed: () => setState(() => _page--),
                    child: Text(
                      '← Previous',
                      style: RunThruTypography.body.copyWith(
                        color: RunThruTokens.shellAccent,
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text('Page $_page', style: RunThruTypography.body),
                ),
                if (catalog.nextUrl != null)
                  TextButton(
                    onPressed: () => setState(() => _page++),
                    child: Text(
                      'Next →',
                      style: RunThruTypography.body.copyWith(
                        color: RunThruTokens.shellAccent,
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildError(Object error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off,
              size: 48,
              color: RunThruTokens.shellTextSecondary,
            ),
            const SizedBox(height: 16),
            Text(
              'Could not load catalog',
              style: RunThruTypography.title.copyWith(
                color: RunThruTokens.shellError,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$error',
              style: RunThruTypography.caption,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: RunThruTokens.shellAccent,
                foregroundColor: RunThruTokens.shellBase,
              ),
              onPressed: () {
                // Force re-fetch by invalidating the provider.
                ref.invalidate(
                  opdsCatalogProvider((query: _query, page: _page)),
                );
              },
              child: Text(
                'Retry',
                style: RunThruTypography.body.copyWith(
                  color: RunThruTokens.shellBase,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Book card ──

class _BookCard extends StatelessWidget {
  const _BookCard({
    required this.entry,
    required this.isDownloading,
    required this.onDownload,
  });

  final OpdsEntry entry;
  final bool isDownloading;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: RunThruDecorations.raisedDecoration(
        RunThruSurface.shell,
        size: RunThruShadowSize.standard,
        borderRadius: 16,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Cover image ──
            Expanded(
              flex: 3,
              child: entry.coverUrl != null
                  ? _AdaptiveImage(url: entry.coverUrl!, fit: BoxFit.cover)
                  : const _CoverPlaceholder(),
            ),

            // ── Info ──
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title,
                      style: RunThruTypography.caption.copyWith(
                        fontWeight: FontWeight.w600,
                        color: RunThruTokens.shellTextPrimary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (entry.author != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        entry.author!,
                        style: RunThruTypography.caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const Spacer(),
                    // ── Download button ──
                    SizedBox(
                      width: double.infinity,
                      height: 30,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: RunThruTokens.shellAccent,
                          foregroundColor: RunThruTokens.shellBase,
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: isDownloading ? null : onDownload,
                        child: Text(
                          isDownloading ? 'Downloading…' : 'Download',
                          style: RunThruTypography.caption.copyWith(
                            color: RunThruTokens.shellBase,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Adaptive image widget that handles both network URLs and data: URIs.
class _AdaptiveImage extends StatelessWidget {
  const _AdaptiveImage({required this.url, this.fit = BoxFit.cover});

  final String url;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    if (url.startsWith('data:')) {
      // Parse data: URI — format is typically "data:image/png;base64,..." or "data:image/jpeg;base64,..."
      try {
        final parts = url.split(',');
        if (parts.length < 2) {
          throw const FormatException('Invalid data: URI format');
        }

        final dataString = parts[1];
        final imageBytes = base64Decode(dataString);

        return Image.memory(
          imageBytes,
          fit: fit,
          errorBuilder: (context, error, stackTrace) {
            appLog('discover', 'cover image (memory) failed error=$error');
            return const _CoverPlaceholder();
          },
        );
      } catch (e) {
        appLog(
          'discover',
          'cover image (memory) decode error url=$url error=$e',
        );
        return const _CoverPlaceholder();
      }
    } else {
      // Regular network URL
      return Image.network(
        url,
        fit: fit,
        errorBuilder: (context, error, stackTrace) {
          appLog(
            'discover',
            'cover image (network) failed url=$url error=$error',
          );
          return const _CoverPlaceholder();
        },
      );
    }
  }
}

/// Placeholder shown when no cover image is available or image fails to load.
class _CoverPlaceholder extends StatelessWidget {
  const _CoverPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: RunThruTokens.shellDarkShadow,
      child: const Center(
        child: Icon(
          Icons.menu_book,
          size: 40,
          color: RunThruTokens.shellTextSecondary,
        ),
      ),
    );
  }
}
