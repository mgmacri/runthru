/// Instapaper connection tile for Settings > Sources.
///
/// Shows connection status (authenticated username, "Not connected") and
/// surfaces the login form or logout action inline.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runthru/design/design.dart';
import 'package:runthru/features/content/providers/instapaper_auth_provider.dart';
import 'package:runthru/widgets/neumorphic_card.dart';

/// Neumorphic source-connection tile for Instapaper.
///
/// Renders inside Settings > Sources. Shows auth state and provides
/// login/logout controls.
class InstapaperAuthTile extends ConsumerWidget {
  /// Creates an [InstapaperAuthTile].
  const InstapaperAuthTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(instapaperAuthProvider);

    return switch (authState) {
      InstapaperAuthChecking() => const _SourceRow(
        icon: Icons.bookmark_outline,
        name: 'Instapaper',
        statusWidget: _StatusChip(label: 'Checking…', ready: false),
        trailing: SizedBox.shrink(),
      ),
      InstapaperAuthUnauthenticated() ||
      InstapaperAuthLegacyFallbackRequired() => _NotConnectedTile(
        onConnect: () => _showLoginSheet(context, ref),
      ),
      InstapaperAuthLoading() => const _SourceRow(
        icon: Icons.bookmark_outline,
        name: 'Instapaper',
        statusWidget: _StatusChip(label: 'Connecting…', ready: false),
        trailing: SizedBox.shrink(),
      ),
      InstapaperAuthAuthenticated(:final user) => _ConnectedTile(
        username: user.username,
        onLogout: () => ref.read(instapaperAuthProvider.notifier).logout(),
      ),
      InstapaperAuthError(:final message) => _ErrorTile(
        message: message,
        onRetry: () => _showLoginSheet(context, ref),
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

class _InstapaperLoginSheetState
    extends ConsumerState<_InstapaperLoginSheet> {
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
    ref.read(instapaperAuthProvider.notifier).login(
      username: email,
      password: _passwordController.text,
    );
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
                disabledBackgroundColor:
                    RunThruTokens.shellAccent.withValues(alpha: 0.5),
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
  const _NotConnectedTile({required this.onConnect});

  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    return _SourceRow(
      icon: Icons.bookmark_outline,
      name: 'Instapaper',
      statusWidget: const _StatusChip(label: 'Not connected', ready: false),
      trailing: SizedBox(
        height: 36,
        child: Semantics(
          button: true,
          label: 'Connect Instapaper',
          child: GestureDetector(
            onTap: onConnect,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: RunThruDecorations.raisedDecoration(
                RunThruSurface.shell,
                size: RunThruShadowSize.small,
                borderRadius: 8,
              ),
              child: Text(
                'Connect',
                style: RunThruTypography.caption.copyWith(
                  color: RunThruTokens.shellAccent,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ConnectedTile extends StatelessWidget {
  const _ConnectedTile({required this.username, required this.onLogout});

  final String username;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return _SourceRow(
      icon: Icons.bookmark_rounded,
      name: 'Instapaper',
      statusWidget: _StatusChip(label: username, ready: true),
      trailing: SizedBox(
        width: 48,
        height: 48,
        child: IconButton(
          onPressed: onLogout,
          icon: const Icon(Icons.logout_rounded, size: 20),
          color: RunThruTokens.shellTextSecondary,
          tooltip: 'Disconnect Instapaper',
        ),
      ),
    );
  }
}

class _ErrorTile extends StatelessWidget {
  const _ErrorTile({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return _SourceRow(
      icon: Icons.bookmark_outline,
      name: 'Instapaper',
      statusWidget: const _StatusChip(
        label: 'Error',
        ready: false,
        color: RunThruTokens.shellError,
      ),
      trailing: SizedBox(
        height: 36,
        child: Semantics(
          button: true,
          label: 'Reconnect Instapaper',
          child: GestureDetector(
            onTap: onRetry,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: RunThruDecorations.raisedDecoration(
                RunThruSurface.shell,
                size: RunThruShadowSize.small,
                borderRadius: 8,
              ),
              child: Text(
                'Reconnect',
                style: RunThruTypography.caption.copyWith(
                  color: RunThruTokens.shellError,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Neumorphic row layout shared by all source tile states.
class _SourceRow extends StatelessWidget {
  const _SourceRow({
    required this.icon,
    required this.name,
    required this.statusWidget,
    required this.trailing,
  });

  final IconData icon;
  final String name;
  final Widget statusWidget;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return NeumorphicCard(
      surface: RunThruSurface.shell,
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 22, color: RunThruTokens.shellAccent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: RunThruTypography.body),
                const SizedBox(height: 2),
                statusWidget,
              ],
            ),
          ),
          const SizedBox(width: 8),
          trailing,
        ],
      ),
    );
  }
}

/// Small status chip: "Connected", "Not connected", username, etc.
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.ready, this.color});

  final String label;
  final bool ready;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final textColor =
        color ??
        (ready ? RunThruTokens.shellReady : RunThruTokens.shellTextSecondary);
    return Text(
      label,
      style: RunThruTypography.caption.copyWith(color: textColor),
    );
  }
}
