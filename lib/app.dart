import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:runthru/core/clipboard_document.dart';
import 'package:runthru/design/design.dart';
import 'package:runthru/features/content/models/shared_content.dart';
import 'package:runthru/features/content/providers/clipboard_detect_provider.dart';
import 'package:runthru/features/content/providers/share_intent_provider.dart';
import 'package:runthru/navigation/app_router.dart';

/// RunThru MaterialApp with ThemeExtension and go_router.
class RunThruApp extends ConsumerWidget {
  const RunThruApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _ContentLifecycleObserver(
      child: MaterialApp.router(
        title: 'RunThru',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: RunThruTokens.shellBase,
          extensions: const [RunThruTokens.instance],
        ),
        routerConfig: appRouter,
      ),
    );
  }
}

/// Platform channel for retrieving the iOS App Group container path.
const _iosFileAccessChannel = MethodChannel('com.runthru/ios_file_access');

/// Listens for [AppLifecycleState.resumed] and triggers content detection.
///
/// On every foreground resume:
/// - Checks clipboard for importable text (≥20 words) via [ClipboardDetect].
/// - On iOS, checks the App Group container for pending shared content.
class _ContentLifecycleObserver extends ConsumerStatefulWidget {
  const _ContentLifecycleObserver({required this.child});

  final Widget child;

  @override
  ConsumerState<_ContentLifecycleObserver> createState() =>
      _ContentLifecycleObserverState();
}

class _ContentLifecycleObserverState
    extends ConsumerState<_ContentLifecycleObserver> {
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(onResume: _onResume);

    // Set up share intent listener first — it takes priority over clipboard.
    // On cold-start via share intent, the platform channel message is queued
    // and delivered once the provider builds. The listener must be active
    // before clipboard detection runs.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _listenForShareIntent();
      // Delay clipboard check slightly so queued share intent messages
      // can be processed first (platform channel delivers async).
      Future<void>.delayed(const Duration(milliseconds: 200), () {
        if (mounted) _onResume();
      });
    });
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    super.dispose();
  }

  /// Navigates to reading screen when share intent produces a document.
  void _listenForShareIntent() {
    // Check current state first — on cold-start the provider may have
    // already transitioned to done before this listener was set up.
    final current = ref.read(shareIntentProvider);
    if (current is ShareIntentDone) {
      _handleShareIntentDone(current);
      return;
    }

    ref.listenManual(shareIntentProvider, (previous, next) {
      if (next is ShareIntentDone) {
        _handleShareIntentDone(next);
      } else if (next is ShareIntentError) {
        _showShareError(next);
      }
    });
  }

  /// Shows a snackbar with the share intent error message.
  void _showShareError(ShareIntentError state) {
    ref.read(shareIntentProvider.notifier).clear();
    if (!mounted) return;

    // Find the nearest ScaffoldMessenger below the router.
    final messenger = appRouter.routerDelegate.navigatorKey.currentContext;
    if (messenger != null) {
      ScaffoldMessenger.of(messenger).showSnackBar(
        SnackBar(
          content: Text(state.message),
          duration: const Duration(seconds: 5),
        ),
      );
    }

    // Navigate to library as fallback.
    appRouter.go('/');
  }

  /// Routes based on share action: read now → reading screen, import → library.
  void _handleShareIntentDone(ShareIntentDone state) {
    if (state.content.action == ShareAction.import_) {
      _importToLibrary(state);
    } else {
      _navigateToReading(state);
    }
  }

  /// Constructs a [ClipboardDocument] and navigates to the reading screen.
  void _navigateToReading(ShareIntentDone state) {
    final doc = ClipboardDocument(
      title: state.content.title ?? 'Shared Content',
      fullText: state.content.data,
      document: state.document,
      pastedAt: DateTime.now(),
    );

    // Clear state to prevent re-triggering on rebuild.
    ref.read(shareIntentProvider.notifier).clear();

    // Navigate to reading screen. Use go() so back returns to library.
    // Use appRouter directly — this widget wraps MaterialApp.router,
    // so GoRouter.of(context) can't find the router above us.
    if (mounted) {
      appRouter.go('/read-clipboard', extra: doc);
    }
  }

  /// Saves shared content as a text file in the library folder and navigates
  /// to the library screen.
  void _importToLibrary(ShareIntentDone state) {
    // Clear state to prevent re-triggering on rebuild.
    ref.read(shareIntentProvider.notifier).clear();

    // Save the content as a text file in the app's shared_imports directory.
    _saveToLibrary(state.content).then((_) {
      if (mounted) {
        appRouter.go('/');
      }
    });
  }

  /// Persists shared text content as a file for later reading.
  Future<void> _saveToLibrary(SharedContent content) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final libraryDir = Directory('${dir.path}/imported');
      if (!libraryDir.existsSync()) {
        libraryDir.createSync(recursive: true);
      }
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final title = content.title ?? 'Shared Content';
      // Sanitise filename — remove path-unsafe characters.
      final safeName = title.replaceAll(RegExp(r'[^\w\s-]'), '').trim();
      final file = File('${libraryDir.path}/${safeName}_$timestamp.txt');
      await file.writeAsString(content.data);
    } on Exception {
      // If save fails, still navigate to library — content was already
      // processed and the user chose "import", not "read now".
    }
  }

  Future<void> _onResume() async {
    // Skip clipboard detection when a share intent is being processed
    // or has completed — share intent takes priority.
    final shareState = ref.read(shareIntentProvider);
    if (shareState is! ShareIntentIdle) return;

    ref.read(clipboardDetectProvider.notifier).checkClipboard();

    if (Platform.isIOS) {
      await _checkIosAppGroup();
    }
  }

  Future<void> _checkIosAppGroup() async {
    try {
      final path = await _iosFileAccessChannel.invokeMethod<String>(
        'getAppGroupPath',
      );
      if (path != null) {
        await ref
            .read(shareIntentProvider.notifier)
            .checkAppGroupContainer(path);
      }
    } on PlatformException {
      // App Group path retrieval failed — silently ignore.
    } on MissingPluginException {
      // Channel not available (e.g. running on Android) — ignore.
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
