/// Instapaper connection tile for Settings > Sources.
///
/// Shows connection status (authenticated username, "Not connected") and
/// surfaces the login form or logout action inline.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runthru/design/design.dart';
import 'package:runthru/features/content/providers/instapaper_auth_provider.dart';
import 'package:runthru/features/content/widgets/brand_icons.dart';
import 'package:runthru/widgets/runthru_shell_widgets.dart';

/// Neumorphic source-connection tile for Instapaper.
///
/// Renders inside Settings > Sources. Shows auth state and provides
/// login/logout controls.
class InstapaperAuthTile extends ConsumerWidget {
  /// Creates an [InstapaperAuthTile].
  const InstapaperAuthTile({super.key, this.showDivider = false});

  /// Whether to draw a hairline divider below this row.
  final bool showDivider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(instapaperAuthProvider);

    return switch (authState) {
      InstapaperAuthChecking() => _SourceRow(
        icon: Icons.bookmark_outline,
        iconWidget: const InstapaperBrandIcon(size: 20),
        name: 'Instapaper',
        statusWidget: Text(
          'Checking…',
          style: RunThruTypography.metadata.copyWith(
            color: RunThruTokens.shellTextSecondary,
          ),
        ),
        trailing: const SizedBox.shrink(),
        showDivider: showDivider,
      ),
      InstapaperAuthUnauthenticated() ||
      InstapaperAuthLegacyFallbackRequired() => _NotConnectedTile(
        onConnect: () => _showLoginSheet(context, ref),
        showDivider: showDivider,
      ),
      InstapaperAuthLoading() => _SourceRow(
        icon: Icons.bookmark_outline,
        iconWidget: const InstapaperBrandIcon(size: 20),
        name: 'Instapaper',
        statusWidget: Text(
          'Connecting…',
          style: RunThruTypography.metadata.copyWith(
            color: RunThruTokens.shellTextSecondary,
          ),
        ),
        trailing: const SizedBox.shrink(),
        showDivider: showDivider,
      ),
      InstapaperAuthAuthenticated(:final user) => _ConnectedTile(
        username: user.username,
        onLogout: () => ref.read(instapaperAuthProvider.notifier).logout(),
        showDivider: showDivider,
      ),
      InstapaperAuthError(:final message) => _ErrorTile(
        message: message,
        onRetry: () => _showLoginSheet(context, ref),
        showDivider: showDivider,
      ),
    };
  }

  void _showLoginSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: RunThruTokens.shellBase,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: const _InstapaperLoginSheet(),
      ),
    );
  }
}

/// Sign-in form bottom sheet for Instapaper xAuth connection.
class _InstapaperLoginSheet extends ConsumerStatefulWidget {
  const _InstapaperLoginSheet();

  @override
  ConsumerState<_InstapaperLoginSheet> createState() =>
      _InstapaperLoginSheetState();
}

class _InstapaperLoginSheetState extends ConsumerState<_InstapaperLoginSheet> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  bool _passwordVisible = false;
  String? _inlineError;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  void _submit() {
    setState(() => _inlineError = null);
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() => _inlineError = 'Enter your Instapaper email or username.');
      return;
    }
    ref
        .read(instapaperAuthProvider.notifier)
        .login(username: email, password: _passwordController.text);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<InstapaperAuthState>(instapaperAuthProvider, (previous, next) {
      if (!mounted) return;
      if (next is InstapaperAuthAuthenticated) {
        Navigator.of(context).pop();
      } else if (next is InstapaperAuthError) {
        setState(() => _inlineError = next.message);
      }
    });

    final authState = ref.watch(instapaperAuthProvider);
    final isLoading = authState is InstapaperAuthLoading;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Sign in to Instapaper', style: RunThruTypography.title),
          const SizedBox(height: 6),
          Text(
            'Your credentials go directly to Instapaper. RunThru stores only a secure token — never your password.',
            style: RunThruTypography.caption.copyWith(
              color: RunThruTokens.shellTextSecondary,
            ),
          ),
          const SizedBox(height: 24),
          _FormField(
            controller: _emailController,
            focusNode: _emailFocus,
            label: 'Email or username',
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.email, AutofillHints.username],
            enabled: !isLoading,
            onSubmitted: (_) => _passwordFocus.requestFocus(),
          ),
          const SizedBox(height: 12),
          _FormField(
            controller: _passwordController,
            focusNode: _passwordFocus,
            label: 'Password',
            obscureText: !_passwordVisible,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.password],
            enabled: !isLoading,
            onSubmitted: (_) => _submit(),
            suffix: IconButton(
              icon: Icon(
                _passwordVisible
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 20,
                color: RunThruTokens.shellTextSecondary,
              ),
              tooltip: _passwordVisible ? 'Hide password' : 'Show password',
              onPressed: isLoading
                  ? null
                  : () => setState(() => _passwordVisible = !_passwordVisible),
            ),
          ),
          if (_inlineError != null) ...[
            const SizedBox(height: 10),
            Text(
              _inlineError!,
              style: RunThruTypography.caption.copyWith(
                color: RunThruTokens.shellError,
              ),
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: isLoading ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: RunThruTokens.shellAccent,
                disabledBackgroundColor: RunThruTokens.shellAccent.withValues(
                  alpha: 0.5,
                ),
                foregroundColor: RunThruTokens.shellBase,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 0,
              ),
              child: isLoading
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: RunThruTokens.shellBase.withValues(alpha: 0.8),
                      ),
                    )
                  : Text(
                      'Connect',
                      style: RunThruTypography.body.copyWith(
                        color: RunThruTokens.shellBase,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'No account? Create one free at instapaper.com',
            style: RunThruTypography.caption.copyWith(
              color: RunThruTokens.shellTextSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Styled form field matching the RunThru shell surface.
class _FormField extends StatelessWidget {
  const _FormField({
    required this.controller,
    required this.focusNode,
    required this.label,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.obscureText = false,
    this.enabled = true,
    this.onSubmitted,
    this.suffix,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String label;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final bool obscureText;
  final bool enabled;
  final ValueChanged<String>? onSubmitted;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      autofillHints: autofillHints,
      autocorrect: false,
      onSubmitted: onSubmitted,
      style: RunThruTypography.body.copyWith(
        color: RunThruTokens.shellTextPrimary,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: RunThruTypography.caption.copyWith(
          color: RunThruTokens.shellTextSecondary,
        ),
        suffixIcon: suffix,
        filled: true,
        fillColor: RunThruTokens.shellBase,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: RunThruTokens.shellTextSecondary.withValues(alpha: 0.25),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(
            color: RunThruTokens.shellAccent,
            width: 1.5,
          ),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: RunThruTokens.shellTextSecondary.withValues(alpha: 0.12),
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
      ),
    );
  }
}

class _NotConnectedTile extends StatelessWidget {
  const _NotConnectedTile({required this.onConnect, this.showDivider = false});

  final VoidCallback onConnect;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return _SourceRow(
      icon: Icons.bookmark_outline,
      iconWidget: const InstapaperBrandIcon(size: 20),
      name: 'Instapaper',
      statusWidget: Text(
        'Not connected',
        style: RunThruTypography.metadata.copyWith(
          color: RunThruTokens.shellTextSecondary,
        ),
      ),
      showDivider: showDivider,
      trailing: Semantics(
        button: true,
        label: 'Connect Instapaper',
        child: GestureDetector(
          onTap: onConnect,
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
    );
  }
}

class _ConnectedTile extends StatelessWidget {
  const _ConnectedTile({
    required this.username,
    required this.onLogout,
    this.showDivider = false,
  });

  final String username;
  final VoidCallback onLogout;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return _SourceRow(
      icon: Icons.bookmark_rounded,
      iconWidget: const InstapaperBrandIcon(size: 20),
      name: 'Instapaper',
      inlineBadge: RunThruStatusPill(
        label: username,
        tone: RunThruStatusTone.ready,
      ),
      statusWidget: Text(
        'Connected',
        style: RunThruTypography.metadata.copyWith(
          color: RunThruTokens.shellTextSecondary,
        ),
      ),
      showDivider: showDivider,
      trailing: Semantics(
        button: true,
        label: 'Disconnect Instapaper',
        child: GestureDetector(
          onTap: onLogout,
          child: Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: RunThruDecorations.designerRaisedSmall(borderRadius: 10),
            child: const Icon(
              Icons.logout_rounded,
              size: 16,
              color: RunThruTokens.shellInkSoft,
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorTile extends StatelessWidget {
  const _ErrorTile({
    required this.message,
    required this.onRetry,
    this.showDivider = false,
  });

  final String message;
  final VoidCallback onRetry;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return _SourceRow(
      icon: Icons.bookmark_outline,
      iconWidget: const InstapaperBrandIcon(size: 20),
      name: 'Instapaper',
      statusWidget: Text(
        message,
        style: RunThruTypography.metadata.copyWith(
          color: RunThruTokens.shellError,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      showDivider: showDivider,
      trailing: Semantics(
        button: true,
        label: 'Reconnect Instapaper',
        child: GestureDetector(
          onTap: onRetry,
          child: Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            decoration: RunThruDecorations.designerRaisedSmall(
              borderRadius: 999,
            ),
            child: Text(
              'Retry',
              style: RunThruTypography.caption.copyWith(
                color: RunThruTokens.shellError,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Flat row layout shared by all source tile states.
class _SourceRow extends StatelessWidget {
  const _SourceRow({
    required this.icon,
    this.iconWidget,
    required this.name,
    this.inlineBadge,
    required this.statusWidget,
    required this.trailing,
    this.showDivider = false,
  });

  final IconData icon;
  final Widget? iconWidget;
  final String name;
  final Widget? inlineBadge;
  final Widget statusWidget;
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
                child: iconWidget ??
                    Icon(icon, size: 20, color: RunThruTokens.shellAccent),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            style: RunThruTypography.rowTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (inlineBadge != null) ...[
                          const SizedBox(width: 7),
                          inlineBadge!,
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    statusWidget,
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
