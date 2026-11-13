import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:runthru/core/document_title.dart';
import 'package:runthru/core/logger.dart';
import 'package:runthru/features/content/models/shared_content.dart';
import 'package:runthru/features/content/services/content_normaliser.dart';
import 'package:runthru/features/content/services/web_page_decoder.dart';
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

/// A failure whose [message] is written for the reader and shown as it is.
class _ShareFailure implements Exception {
  const _ShareFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// What the reader is told when something shared cannot be opened. Only
/// sentences written for them are shown: an error's own text ("Exception: …",
/// "FormatException: …", a file path) never is.
String _shareErrorMessage(Object error) => switch (error) {
  _ShareFailure(:final message) => message,
  UnsupportedPdfError() => 'RunThru could not find readable text in this file.',
  PdfTimeoutError() => 'This file took too long to open.',
  _ =>
    'RunThru could not open what was shared. '
        'Try copying the text and pasting it in RunThru instead.',
};

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
      case 'onReadClipboard':
        await _readClipboardAndIngest();
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
      _fetchedTitle = null;
      final document = await _extractContent(content);
      // A shared link takes the page's own title ("Lighthouse - Wikipedia").
      final titled = content.title == null && _fetchedTitle != null
          ? SharedContent(
              type: content.type,
              data: content.data,
              title: _fetchedTitle,
              mimeType: content.mimeType,
              receivedAt: content.receivedAt,
              action: content.action,
            )
          : content;
      state = ShareIntentState.done(content: titled, document: document);
    } catch (e) {
      // Errors as well as exceptions: left uncaught, the state would stay
      // "processing" for the rest of the session.
      appLog('share_intent', 'could not open shared content: ${e.runtimeType}');
      state = ShareIntentState.error(
        message: _shareErrorMessage(e),
        content: content,
      );
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

  /// Reads text from the system clipboard and ingests it for immediate reading.
  ///
  /// Triggered by the "Read Clipboard" app shortcut. If the clipboard is empty
  /// or has no text, transitions to error state.
  Future<void> _readClipboardAndIngest() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim();
      if (text == null || text.isEmpty) {
        state = const ShareIntentState.error(
          message: 'Clipboard is empty. Copy some text first.',
        );
        return;
      }
      final content = SharedContent.text(
        text,
        title: titleFromText(text) ?? 'Clipboard',
      );
      await ingest(content);
    } catch (e) {
      appLog('share_intent', 'could not read the clipboard: ${e.runtimeType}');
      state = const ShareIntentState.error(
        message: 'RunThru could not read the clipboard.',
      );
    }
  }

  Future<ExtractedDocument> _extractContent(SharedContent content) async {
    switch (content.type) {
      case SharedContentType.text:
        // LLM apps (ChatGPT, Claude, Gemini) share as text/plain but
        // content is typically markdown-formatted. Detect and route.
        final contentType = _looksLikeMarkdown(content.data)
            ? ContentType.markdown
            : ContentType.plainText;
        return ContentNormaliser.normalise(content.data, contentType);

      case SharedContentType.htmlText:
        return ContentNormaliser.normalise(content.data, ContentType.html);

      case SharedContentType.pdfFile:
        return extractPdfInIsolate(content.data);

      case SharedContentType.epubFile:
        return extractEpubInIsolate(content.data);

      case SharedContentType.url:
        return _fetchAndExtractUrl(content.data);
    }
  }

  /// Known LLM/chat domains that share links instead of text content.
  ///
  /// These sites require authentication to view shared conversations,
  /// so fetching the URL returns a login page, not the actual content.
  static const _llmDomains = [
    'chatgpt.com',
    'chat.openai.com',
    'claude.ai',
    'gemini.google.com',
    'bard.google.com',
    'copilot.microsoft.com',
    'poe.com',
    'perplexity.ai',
    'you.com',
    'pi.ai',
  ];

  /// Title of the last fetched page, picked up by [ingest].
  String? _fetchedTitle;

  /// Fetches a URL and extracts readable content from the HTML response.
  ///
  /// Detects known LLM domains that share links instead of content and
  /// shows a helpful error. For other URLs, fetches HTML and normalises it.
  /// Follows redirects (up to 5). Gives up when the site does not connect
  /// within 15 seconds, does not answer within 20, or has not sent the
  /// whole page within 30, and when the page is larger than
  /// [kMaxWebPageBytes].
  Future<ExtractedDocument> _fetchAndExtractUrl(String url) async {
    // Check for known LLM domains — they share links, not content.
    final uri = Uri.tryParse(url);
    if (uri != null) {
      final host = uri.host.toLowerCase();
      for (final domain in _llmDomains) {
        if (host == domain || host.endsWith('.$domain')) {
          throw const _ShareFailure(
            'This app shared a link to the conversation, not the text. '
            'To read in RunThru:\n'
            '1. Tap the Copy button on the response\n'
            '2. Open RunThru and paste from clipboard',
          );
        }
      }
    }

    // Security: never fetch over cleartext. Dart's HttpClient bypasses the
    // platform cleartext blocks (Android networkSecurityConfig / iOS ATS),
    // so http:// links are upgraded to https before the request is made.
    var fetchUri = Uri.parse(url);
    if (fetchUri.scheme == 'http') {
      fetchUri = fetchUri.replace(scheme: 'https');
    }
    if (fetchUri.scheme != 'https') {
      throw const _ShareFailure(
        'Only web links can be fetched. '
        'Try copying the text and pasting it in RunThru instead.',
      );
    }

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(fetchUri);
      // Identify as a browser so sites return full HTML, not API responses.
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/125.0.0.0 Mobile Safari/537.36',
      );
      request.headers.set(HttpHeaders.acceptHeader, 'text/html, */*');
      request.followRedirects = true;
      request.maxRedirects = 5;

      final response = await request.close().timeout(_answerTimeout);
      // Security: reject any redirect hop that downgraded to cleartext.
      if (response.redirects.any((r) => r.location.scheme == 'http')) {
        throw const _ShareFailure(
          'The shared link redirected to an insecure connection. '
          'Try copying the text and pasting it in RunThru instead.',
        );
      }
      if (response.statusCode != 200) {
        throw _ShareFailure(
          'Could not fetch the shared link (HTTP ${response.statusCode}). '
          'Try copying the text and pasting it in RunThru instead.',
        );
      }

      // A link to a file (a PDF, an image, a download) is not a page.
      final type = response.headers.contentType;
      if (type != null &&
          type.primaryType != 'text' &&
          !type.subType.contains('html') &&
          !type.subType.contains('xml')) {
        throw const _ShareFailure(
          'That link is not a web page RunThru can read. '
          'Try copying the text and pasting it in RunThru instead.',
        );
      }
      if (response.contentLength > kMaxWebPageBytes) {
        throw const _ShareFailure(_pageTooLarge);
      }
      final Uint8List bytes;
      try {
        bytes = await readWebPage(response).timeout(_downloadTimeout);
      } on WebPageTooLarge {
        throw const _ShareFailure(_pageTooLarge);
      }
      // The page's own encoding, not always UTF-8: an older page in
      // Windows-1252 used to fail to open at its first accented letter.
      final body = decodeWebPage(bytes, charset: type?.charset);
      if (body == null) {
        throw const _ShareFailure(
          'That page is in a text encoding RunThru cannot read. '
          'Try copying the text and pasting it in RunThru instead.',
        );
      }
      if (body.trim().isEmpty) {
        throw const _ShareFailure(
          'The shared link returned no content. '
          'Try copying the text and pasting it in RunThru instead.',
        );
      }

      _fetchedTitle = ContentNormaliser.htmlTitle(body);
      return ContentNormaliser.normalise(body, ContentType.html);
    } on SocketException {
      throw const _ShareFailure(
        'No internet connection. '
        'Copy the text and paste it in RunThru instead.',
      );
    } on HttpException {
      throw const _ShareFailure(
        'Could not fetch the shared link. '
        'Try copying the text and pasting it in RunThru instead.',
      );
    } on TimeoutException {
      throw const _ShareFailure(
        'That page took too long to load. '
        'Try again, or copy the text and paste it in RunThru instead.',
      );
    } finally {
      // Forced: a download given up on (too slow, too large) is cut off
      // rather than left to finish in the background.
      client.close(force: true);
    }
  }

  /// How long a site may take to start answering once connected.
  static const Duration _answerTimeout = Duration(seconds: 20);

  /// How long the whole page may take to arrive.
  static const Duration _downloadTimeout = Duration(seconds: 30);

  static const String _pageTooLarge =
      'That page is too large to open. '
      'Try copying the text and pasting it in RunThru instead.';

  /// Heuristic: does this text look like markdown?
  ///
  /// Checks for common markdown indicators that plain prose wouldn't have.
  /// Conservative — only triggers on clear markdown signals.
  static bool _looksLikeMarkdown(String text) {
    // Check first 2000 chars to avoid scanning huge documents.
    final sample = text.length > 2000 ? text.substring(0, 2000) : text;

    var signals = 0;
    if (RegExp(r'^#{1,6}\s', multiLine: true).hasMatch(sample)) signals++;
    if (sample.contains('```')) signals++;
    if (RegExp(r'\*\*[^*]+\*\*').hasMatch(sample)) signals++;
    if (RegExp(r'^\s*[-*+]\s', multiLine: true).hasMatch(sample)) signals++;
    if (RegExp(r'\[.+\]\(.+\)').hasMatch(sample)) signals++;

    // Two or more signals → treat as markdown.
    return signals >= 2;
  }
}
