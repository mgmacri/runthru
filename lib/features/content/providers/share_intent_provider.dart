import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:runthru/core/clipboard_document.dart';
import 'package:runthru/features/content/models/shared_content.dart';
import 'package:runthru/services/epub_extractor.dart';
import 'package:runthru/services/models.dart';
import 'package:runthru/services/pdf_extractor.dart';

part 'share_intent_provider.g.dart';

/// State for the share intent ingestion pipeline.
sealed class ShareIntentState {
  /// No pending share intent.
  const factory ShareIntentState.idle() = ShareIntentIdle;

  /// Currently processing a shared item.
  const factory ShareIntentState.processing({
    required SharedContent content,
    double progress,
  }) = ShareIntentProcessing;

  /// Successfully ingested shared content.
  const factory ShareIntentState.done({
    required SharedContent content,
    required ExtractedDocument document,
  }) = ShareIntentDone;

  /// An error occurred during ingestion.
  const factory ShareIntentState.error({
    required String message,
    SharedContent? content,
  }) = ShareIntentError;
}

/// No pending share intent.
class ShareIntentIdle implements ShareIntentState {
  /// Creates an idle state.
  const ShareIntentIdle();
}

/// Currently processing a shared item.
class ShareIntentProcessing implements ShareIntentState {
  /// Creates a processing state.
  const ShareIntentProcessing({required this.content, this.progress = 0.0});

  /// The content being processed.
  final SharedContent content;

  /// Progress from 0.0 to 1.0.
  final double progress;
}

/// Successfully ingested shared content.
class ShareIntentDone implements ShareIntentState {
  /// Creates a done state.
  const ShareIntentDone({required this.content, required this.document});

  /// The original shared content.
  final SharedContent content;

  /// The extracted document ready for reading.
  final ExtractedDocument document;
}

/// An error occurred during ingestion.
class ShareIntentError implements ShareIntentState {
  /// Creates an error state.
  const ShareIntentError({required this.message, this.content});

  /// Human-readable error description.
  final String message;

  /// The content that failed, if available.
  final SharedContent? content;
}

/// Platform channel name for share intent communication.
const String _shareIntentChannel = 'com.runthru/share_intent';

/// Manages incoming share intents from Android and iOS.
///
/// Listens for shared content via platform channel (Android) and
/// App Group container (iOS). Routes content through the appropriate
/// extractor to produce an [ExtractedDocument].
///
/// All content stays on-device only — no cloud upload.
@Riverpod(keepAlive: true)
class ShareIntent extends _$ShareIntent {
  MethodChannel? _channel;

  @override
  ShareIntentState build() {
    _setupChannel();
    return const ShareIntentState.idle();
  }

  void _setupChannel() {
    _channel = const MethodChannel(_shareIntentChannel);
    _channel!.setMethodCallHandler(_handleMethodCall);
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onSharedContent':
        final args = call.arguments as Map<dynamic, dynamic>;
        final map = args.cast<String, dynamic>();
        final content = SharedContent.fromMap(map);
        await ingest(content);
        return null;
      default:
        return null;
    }
  }

  /// Process shared content from any source (share intent, file picker, etc.).
  ///
  /// Routes to the appropriate extractor based on [SharedContent.type].
  /// Content is stored on-device only.
  Future<void> ingest(SharedContent content) async {
    state = ShareIntentState.processing(content: content);
    try {
      final document = await _extractContent(content);
      state = ShareIntentState.done(content: content, document: document);
    } on Exception catch (e) {
      state = ShareIntentState.error(message: e.toString(), content: content);
    }
  }

  /// Check the iOS App Group container for pending shared content.
  ///
  /// Called on [AppLifecycleState.resumed] on iOS. Reads the shared
  /// content JSON file, processes it, then deletes the file.
  Future<void> checkAppGroupContainer(String appGroupPath) async {
    final file = File('$appGroupPath/shared_content.json');
    if (!file.existsSync()) return;

    try {
      final jsonStr = await file.readAsString();
      final map = json.decode(jsonStr) as Map<String, dynamic>;
      final content = SharedContent.fromMap(map);

      // Delete the file immediately after reading to prevent re-processing.
      await file.delete();

      await ingest(content);
    } on FormatException {
      // Malformed JSON — delete and ignore.
      await file.delete();
    }
  }

  /// Resets state back to idle (e.g. after user navigates to reading).
  void clear() {
    state = const ShareIntentState.idle();
  }

  Future<ExtractedDocument> _extractContent(SharedContent content) async {
    switch (content.type) {
      case SharedContentType.text:
        final doc = ClipboardDocument.fromClipboardText(content.data);
        return doc.document;

      case SharedContentType.htmlText:
        // Strip HTML and process as text for now.
        // Will be replaced by ContentNormaliser in E1.3.2.
        final stripped = _basicHtmlStrip(content.data);
        final doc = ClipboardDocument.fromClipboardText(stripped);
        return doc.document;

      case SharedContentType.pdfFile:
        return extractPdfInIsolate(content.data);

      case SharedContentType.epubFile:
        return extractEpubInIsolate(content.data);

      case SharedContentType.url:
        // URL fetching will be added when dio integration is wired.
        // For now, treat the URL as text content.
        final doc = ClipboardDocument.fromClipboardText(content.data);
        return doc.document;
    }
  }

  /// Basic HTML tag stripping for share intent HTML content.
  /// A more robust version lives in ContentNormaliser (E1.3.2).
  static String _basicHtmlStrip(String html) {
    var text = html;
    // Remove script and style blocks.
    text = text.replaceAll(RegExp(r'<style[^>]*>[\s\S]*?</style>'), '');
    text = text.replaceAll(RegExp(r'<script[^>]*>[\s\S]*?</script>'), '');
    // Replace block elements with newlines.
    text = text.replaceAll(RegExp(r'<br\s*/?>'), '\n');
    text = text.replaceAll(RegExp(r'</(p|div|h[1-6]|li)>'), '\n');
    // Strip remaining tags.
    text = text.replaceAll(RegExp(r'<[^>]+>'), ' ');
    // Decode common entities.
    text = text
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&nbsp;', ' ');
    // Collapse whitespace.
    text = text.replaceAll(RegExp(r'[ \t]+'), ' ');
    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return text.trim();
  }
}
