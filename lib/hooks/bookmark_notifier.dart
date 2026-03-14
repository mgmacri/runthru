import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speedy_boy/store/config.dart';
import 'package:speedy_boy/store/models.dart';

/// Tracks and persists reading position for a given PDF file.
class BookmarkNotifier extends StateNotifier<int> with WidgetsBindingObserver {
  BookmarkNotifier(this._ref, this._filePath) : super(0) {
    WidgetsBinding.instance.addObserver(this);
    _autoSaveTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _persist(),
    );
  }

  final Ref _ref;
  final String _filePath;
  Timer? _autoSaveTimer;

  void updateIndex(int index) {
    state = index;
  }

  Future<void> _persist() async {
    await _ref.read(configProvider.notifier).updateBookmark(
          _filePath,
          BookmarkData(
            wordIndex: state,
            timestamp: DateTime.now(),
          ),
        );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _persist();
    }
  }

  Future<void> save() => _persist();

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _persist();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

/// Family provider keyed by filePath.
final bookmarkProvider =
    StateNotifierProvider.family<BookmarkNotifier, int, String>(
  BookmarkNotifier.new,
);
