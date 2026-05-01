import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:runthru/core/clipboard_document.dart';

/// Service to read text from the system clipboard (Rule 28).
///
/// Only reads when explicitly called — never auto-reads. Returns null for
/// empty, too-short, or non-text clipboard contents.
///
/// Text parsing (markdown stripping + sentence splitting) runs in a
/// background isolate to avoid blocking the main event loop (Rule 11).
class ClipboardService {
  /// Minimum character count for clipboard text to be considered readable.
  static const int minTextLength = 10;

  /// Read text from the system clipboard and parse it into a
  /// [ClipboardDocument]. Returns null if the clipboard is empty or the
  /// text is shorter than [minTextLength] characters.
  ///
  /// Rule 28 — clipboard is only read on explicit user action.
  /// Rule 11 — parsing runs in a background isolate.
  Future<ClipboardDocument?> readFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text == null || data!.text!.trim().length < minTextLength) {
      return null;
    }
    return Isolate.run(() => ClipboardDocument.fromClipboardText(data.text!));
  }
}
