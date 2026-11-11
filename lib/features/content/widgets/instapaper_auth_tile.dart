/// Instapaper connection tile for Settings > Sources.
///
/// Shows connection status (authenticated username, "Not connected") and
/// surfaces the login form or logout action inline.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runthru/design/design.dart';
import 'package:runthru/features/content/providers/instapaper_auth_provider.dart';
import 'package:runthru/features/content/providers/instapaper_bookmarks_provider.dart';
import 'package:runthru/features/content/widgets/brand_icons.dart';
import 'package:runthru/widgets/runthru_shell_widgets.dart';

/// Smallest tap target the row's controls may have.
const double _minTapTarget = 48;

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
        name: 'Instapaper',
        statusWidget: const _StatusText('Checking…'),
        trailing: const SizedBox.shrink(),
        showDivider: showDivider,
      ),
      InstapaperAuthUnauthenticated() ||
      InstapaperAuthLegacyFallbackRequired() => _SourceRow(
        name: 'Instapaper',
        statusWidget: const _StatusText('Not connected'),
        showDivider: showDivider,
        trailing: _PillButton(
          label: 'Connect',
          semanticsLabel: 'Connect Instapaper',
          onTap: () => _showLoginSheet(context, ref),
        ),
      ),
      InstapaperAuthLoading() => _SourceRow(
        name: 'Instapaper',
        statusWidget: const _StatusText('Connecting…'),
        trailing: const SizedBox.shrink(),
        showDivider: showDivider,
      ),
      InstapaperAuthAuthenticated(:final user) => _SourceRow(
        name: 'Instapaper',
        // A connection restored before Instapaper could be asked has no
        // name yet.
        inlineBadge: user.username.trim().isEmpty
            ? null
            : RunThruStatusPill(
                label: user.username,
                tone: RunThruStatusTone.ready,
              ),
        statusWidget: const _StatusText('Connected'),
        showDivider: showDivider,
        trailing: _DisconnectButton(
          onTap: () => _confirmDisconnect(context, ref),
        ),
      ),
      InstapaperAuthError(:final message) => _SourceRow(
        name: 'Instapaper',
        statusWidget: _StatusText(message, error: true, maxLines: 3),
        showDivider: showDivider,
        trailing: _PillButton(
          label: 'Reconnect',
          semanticsLabel: 'Reconnect Instapaper',
          color: RunThruTokens.shellError,
          onTap: () => _showLoginSheet(context, ref),
        ),
      ),
    };
  }

  Future<void> _showLoginSheet(BuildContext context, WidgetRef ref) async {
    // Taken now: the row may be gone by the time the sheet closes.
    final auth = ref.read(instapaperAuthProvider.notifier);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: RunThruTokens.shellBase,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => const _InstapaperLoginSheet(),
    );
    // A sign-in that failed was reported in the sheet; the row goes back to
    // "Not connected" instead of carrying the error around.
    auth.dismissError();
  }

  Future<void> _confirmDisconnect(BuildContext context, WidgetRef ref) async {
    final auth = ref.read(instapaperAuthProvider.notifier);
    final queue = ref.read(instapaperSyncQueueProvider);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: RunThruTokens.shellBase,
        title: Text(
          'Disconnect Instapaper?',
          style: RunThruTypography.title.copyWith(
            color: RunThruTokens.shellTextPrimary,
          ),
        ),
        content: Text(
          'Your articles stay in your Instapaper account. '
          'You can connect again at any time.',
          style: RunThruTypography.body.copyWith(
            color: RunThruTokens.shellTextSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              'Cancel',
              style: RunThruTypography.body.copyWith(
                color: RunThruTokens.shellTextSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              'Disconnect',
              style: RunThruTypography.body.copyWith(
                color: RunThruTokens.shellError,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    // Reading positions not sent yet go out first, while the connection
    // still exists; signing out discards what is left.
    await queue.drain().timeout(const Duration(seconds: 4), onTimeout: () {});
    await auth.logout();
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
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() => _inlineError = 'Enter your Instapaper email or username.');
      _emailFocus.requestFocus();
      return;
    }
    setState(() => _inlineError = null);
    // An empty password is valid: many Instapaper accounts have none.
    ref
        .read(instapaperAuthProvider.notifier)
        .login(username: email, password: _passwordController.text);
  }

  void _clearError() {
    if (_inlineError != null) setState(() => _inlineError = null);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<InstapaperAuthState>(instapaperAuthProvider, (previous, next) {
      if (!mounted) return;
      if (next is InstapaperAuthAuthenticated) {
        // Offer to save the password only for a sign-in that worked.
        TextInput.finishAutofillContext();
        Navigator.of(context).pop();
      } else if (next is InstapaperAuthError) {
        setState(() => _inlineError = next.message);
      }
    });

    final authState = ref.watch(instapaperAuthProvider);
    final isLoading = authState is InstapaperAuthLoading;

    // The keyboard's height as this sheet sees it. (The screen behind the
    // sheet cannot be asked: its scaffold has already taken the keyboard
    // out of its own layout, so it reports none.)
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 36),
        child: AutofillGroup(
          onDisposeAction: AutofillContextAction.cancel,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: const Text(
                  'Sign in to Instapaper',
                  style: RunThruTypography.title,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Your email and password go straight to Instapaper. '
                'RunThru keeps only the sign-in token it gets back, '
                'never your password.',
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
                autofillHints: const [
                  AutofillHints.username,
                  AutofillHints.email,
                ],
                enabled: !isLoading,
                onChanged: (_) => _clearError(),
                onSubmitted: (_) => _passwordFocus.requestFocus(),
              ),
              const SizedBox(height: 12),
              _FormField(
                controller: _passwordController,
                focusNode: _passwordFocus,
                label: 'Password, if you have one',
                obscureText: !_passwordVisible,
                keyboardType: TextInputType.visiblePassword,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
                enabled: !isLoading,
                onChanged: (_) => _clearError(),
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
                      : () => setState(
                          () => _passwordVisible = !_passwordVisible,
                        ),
                ),
              ),
              // Always present, so a new message is announced when it
              // appears.
              Semantics(
                liveRegion: true,
                child: _inlineError == null
                    ? const SizedBox(height: 0)
                    : Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          _inlineError!,
                          style: RunThruTypography.caption.copyWith(
                            color: RunThruTokens.shellError,
                          ),
                        ),
                      ),
              ),
              const SizedBox(height: 20),
              Semantics(
                liveRegion: true,
                child: SizedBox(
                  height: _minTapTarget,
                  child: ElevatedButton(
                    onPressed: isLoading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: RunThruTokens.shellAccent,
                      disabledBackgroundColor: RunThruTokens.shellAccent
                          .withValues(alpha: 0.5),
                      foregroundColor: RunThruTokens.shellBase,
                      disabledForegroundColor: RunThruTokens.shellBase,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      elevation: 0,
                    ),
                    // Words, not a spinner: nothing here moves, so there is
                    // nothing to switch off for reduced motion.
                    child: Text(
                      isLoading ? 'Connecting…' : 'Connect',
                      style: RunThruTypography.body.copyWith(
                        color: RunThruTokens.shellBase,
                        fontWeight: FontWeight.w600,
                      ),
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
        ),
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
    this.onChanged,
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
  final ValueChanged<String>? onChanged;
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
      enableSuggestions: false,
      onChanged: onChanged,
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

/// The line under the source's name. A live region: it changes as the
/// connection does ("Checking…", "Connected", an error).
class _StatusText extends StatelessWidget {
  const _StatusText(this.text, {this.error = false, this.maxLines = 1});

  final String text;
  final bool error;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Text(
        text,
        style: RunThruTypography.metadata.copyWith(
          color: error
              ? RunThruTokens.shellError
              : RunThruTokens.shellTextSecondary,
        ),
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// A raised pill ("Connect", "Reconnect"). The pill is drawn 34dp high; the
/// tap target around it is 48dp.
class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.label,
    required this.semanticsLabel,
    required this.onTap,
    this.color = RunThruTokens.shellAccent,
  });

  final String label;
  final String semanticsLabel;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticsLabel,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: _minTapTarget,
            minHeight: _minTapTarget,
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
                label,
                style: RunThruTypography.caption.copyWith(
                  color: color,
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

/// The square "disconnect" control: drawn 34dp, tappable at 48dp.
class _DisconnectButton extends StatelessWidget {
  const _DisconnectButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Disconnect Instapaper',
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: _minTapTarget,
          height: _minTapTarget,
          child: Center(
            child: Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: RunThruDecorations.designerRaisedSmall(
                borderRadius: 10,
              ),
              child: const Icon(
                Icons.logout_rounded,
                size: 16,
                color: RunThruTokens.shellInkSoft,
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
    required this.name,
    this.inlineBadge,
    required this.statusWidget,
    required this.trailing,
    this.showDivider = false,
  });

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
          // 6 + the 48dp control + 6 keeps the row at its 60dp height.
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
                child: const InstapaperBrandIcon(size: 20),
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
                          Flexible(child: inlineBadge!),
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
