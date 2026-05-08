/// Instapaper section widget for the library screen.
///
/// Shows a login prompt when unauthenticated, or a scrollable list of
/// saved articles when authenticated. Tapping a bookmark triggers import.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runthru/design/design.dart';
import 'package:runthru/features/content/models/instapaper_bookmark.dart';
import 'package:runthru/features/content/providers/instapaper_auth_provider.dart';
import 'package:runthru/features/content/providers/instapaper_bookmarks_provider.dart';

/// Instapaper section for the library screen.
///
/// Shows a login prompt when unauthenticated, or a list of saved
/// articles when authenticated. Tapping a bookmark triggers article import.
class InstapaperSection extends ConsumerWidget {
  /// Creates an [InstapaperSection] widget.
  const InstapaperSection({super.key, this.onBookmarkTap});

  /// Called when user taps a bookmark to import.
  final void Function(InstapaperBookmark bookmark)? onBookmarkTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(instapaperAuthProvider);

    return switch (authState) {
      InstapaperAuthUnauthenticated() => const _LoginPrompt(),
      InstapaperAuthLoading() => const _LoadingState(),
      InstapaperAuthAuthenticated(:final user) => _BookmarkList(
        username: user.username,
        onBookmarkTap: onBookmarkTap,
      ),
      InstapaperAuthError(:final message) => _ErrorState(message: message),
    };
  }
}

/// Login form for Instapaper xAuth authentication.
class _LoginPrompt extends ConsumerStatefulWidget {
  const _LoginPrompt();

  @override
  ConsumerState<_LoginPrompt> createState() => _LoginPromptState();
}

class _LoginPromptState extends ConsumerState<_LoginPrompt> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _submit() {
    final username = _usernameController.text.trim();
    if (username.isEmpty) return;

    ref
        .read(instapaperAuthProvider.notifier)
        .login(username: username, password: _passwordController.text);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Instapaper', style: RunThruTypography.title),
          const SizedBox(height: 12),
          TextField(
            controller: _usernameController,
            decoration: InputDecoration(
              labelText: 'Email or username',
              labelStyle: RunThruTypography.caption.copyWith(
                color: RunThruTokens.shellTextSecondary,
              ),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(
                  color: RunThruTokens.shellTextSecondary.withValues(
                    alpha: 0.4,
                  ),
                ),
              ),
              focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: RunThruTokens.shellAccent),
              ),
            ),
            style: RunThruTypography.body.copyWith(
              color: RunThruTokens.shellTextPrimary,
            ),
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autocorrect: false,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _passwordController,
            decoration: InputDecoration(
              labelText: 'Password, if you have one',
              labelStyle: RunThruTypography.caption.copyWith(
                color: RunThruTokens.shellTextSecondary,
              ),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(
                  color: RunThruTokens.shellTextSecondary.withValues(
                    alpha: 0.4,
                  ),
                ),
              ),
              focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: RunThruTokens.shellAccent),
              ),
            ),
            style: RunThruTypography.body.copyWith(
              color: RunThruTokens.shellTextPrimary,
            ),
            obscureText: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: RunThruTokens.shellAccent,
                foregroundColor: RunThruTokens.shellOnError,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                'Sign in',
                style: RunThruTypography.body.copyWith(
                  color: RunThruTokens.shellOnError,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bookmark list shown when authenticated.
class _BookmarkList extends ConsumerWidget {
  const _BookmarkList({required this.username, this.onBookmarkTap});

  /// The authenticated user's display name.
  final String username;

  /// Called when a bookmark tile is tapped.
  final void Function(InstapaperBookmark bookmark)? onBookmarkTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookmarksAsync = ref.watch(instapaperBookmarksProvider);
    final importState = ref.watch(instapaperArticleImportProvider);

    ref.listen(instapaperArticleImportProvider, (prev, next) {
      // Navigation is handled by LibraryScreen's listener — only clear state here.
      if (next is ArticleImportDone) {
        ref.read(instapaperArticleImportProvider.notifier).clear();
      }
    });

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Section header
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Instapaper', style: RunThruTypography.title),
                    Text(
                      username,
                      style: RunThruTypography.caption.copyWith(
                        color: RunThruTokens.shellTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 48,
                width: 48,
                child: IconButton(
                  onPressed: () =>
                      ref.read(instapaperAuthProvider.notifier).logout(),
                  icon: const Icon(Icons.logout_rounded),
                  color: RunThruTokens.shellTextSecondary,
                  tooltip: 'Sign out of Instapaper',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Import error banner
          if (importState is ArticleImportError)
            _ImportErrorBanner(
              message: importState.message,
              onDismiss: () =>
                  ref.read(instapaperArticleImportProvider.notifier).clear(),
            ),
          // Bookmark data
          bookmarksAsync.when(
            data: (bookmarks) {
              if (bookmarks.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'No saved articles',
                    style: RunThruTypography.body.copyWith(
                      color: RunThruTokens.shellTextSecondary,
                    ),
                  ),
                );
              }
              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: bookmarks.length,
                separatorBuilder: (_, __) => const Divider(
                  color: RunThruTokens.shellDarkShadow,
                  height: 1,
                ),
                itemBuilder: (context, index) {
                  final bookmark = bookmarks[index];
                  final isLoading =
                      importState is ArticleImportLoading &&
                      importState.bookmarkId == bookmark.bookmarkId;
                  return _BookmarkTile(
                    bookmark: bookmark,
                    isLoading: isLoading,
                    onTap: (bm) => ref
                        .read(instapaperArticleImportProvider.notifier)
                        .importArticle(bm),
                  );
                },
              );
            },
            loading: () => const _LoadingState(),
            error: (error, _) => _InlineErrorState(
              message: error.toString(),
              onRetry: () => ref.invalidate(instapaperBookmarksProvider),
            ),
          ),
        ],
      ),
    );
  }
}

/// Individual bookmark tile with title, domain, and progress.
class _BookmarkTile extends StatelessWidget {
  const _BookmarkTile({
    required this.bookmark,
    this.isLoading = false,
    this.onTap,
  });

  /// The bookmark to display.
  final InstapaperBookmark bookmark;

  /// Whether this tile is currently loading.
  final bool isLoading;

  /// Called when the tile is tapped.
  final void Function(InstapaperBookmark bookmark)? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${bookmark.title}, ${bookmark.domain}',
      child: InkWell(
        onTap: isLoading || onTap == null ? null : () => onTap!(bookmark),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        bookmark.title.isNotEmpty
                            ? bookmark.title
                            : bookmark.url,
                        style: RunThruTypography.body.copyWith(
                          color: isLoading
                              ? RunThruTokens.shellTextSecondary
                              : RunThruTokens.shellTextPrimary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isLoading ? 'Importing\u2026' : bookmark.domain,
                        style: RunThruTypography.caption.copyWith(
                          color: RunThruTokens.shellTextSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (isLoading)
                  const Padding(
                    padding: EdgeInsets.only(left: 12),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: _ImportSpinner(),
                    ),
                  )
                else if (bookmark.hasProgress)
                  Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.auto_stories_rounded,
                          size: 16,
                          color: RunThruTokens.shellAccent,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          bookmark.progressLabel,
                          style: RunThruTypography.caption.copyWith(
                            color: RunThruTokens.shellAccent,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Error state with icon and retry button.
class _ErrorState extends ConsumerWidget {
  const _ErrorState({required this.message});

  /// The error message to display.
  final String message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: RunThruTokens.shellError,
                size: 20,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  message,
                  style: RunThruTypography.body.copyWith(
                    color: RunThruTokens.shellError,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 48,
            child: TextButton(
              onPressed: () =>
                  ref.read(instapaperAuthProvider.notifier).logout(),
              child: Text(
                'Try again',
                style: RunThruTypography.body.copyWith(
                  color: RunThruTokens.shellAccent,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Inline error with retry for bookmark fetch failures.
class _InlineErrorState extends StatelessWidget {
  const _InlineErrorState({required this.message, required this.onRetry});

  /// The error message to display.
  final String message;

  /// Called when the retry button is pressed.
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: RunThruTokens.shellError,
                size: 16,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Failed to load bookmarks',
                  style: RunThruTypography.caption.copyWith(
                    color: RunThruTokens.shellError,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 48,
            child: TextButton(
              onPressed: onRetry,
              child: Text(
                'Retry',
                style: RunThruTypography.body.copyWith(
                  color: RunThruTokens.shellAccent,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Subtle loading placeholder.
class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Text(
        'Loading\u2026',
        style: RunThruTypography.caption.copyWith(
          color: RunThruTokens.shellTextSecondary,
        ),
      ),
    );
  }
}

/// Error banner shown when an article import fails.
class _ImportErrorBanner extends StatelessWidget {
  const _ImportErrorBanner({required this.message, required this.onDismiss});

  /// The error message to display.
  final String message;

  /// Called when the user dismisses the error.
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: RunThruTokens.shellError,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: RunThruTypography.caption.copyWith(
                color: RunThruTokens.shellError,
              ),
            ),
          ),
          SizedBox(
            width: 48,
            height: 48,
            child: IconButton(
              onPressed: onDismiss,
              icon: const Icon(Icons.close_rounded, size: 16),
              color: RunThruTokens.shellTextSecondary,
              tooltip: 'Dismiss error',
            ),
          ),
        ],
      ),
    );
  }
}

/// Custom pulsing dot spinner (no raw CircularProgressIndicator).
class _ImportSpinner extends StatefulWidget {
  const _ImportSpinner();

  @override
  State<_ImportSpinner> createState() => _ImportSpinnerState();
}

class _ImportSpinnerState extends State<_ImportSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        return Opacity(
          opacity: 0.3 + 0.7 * _controller.value,
          child: Container(
            width: 16,
            height: 16,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: RunThruTokens.shellAccent,
            ),
          ),
        );
      },
    );
  }
}
