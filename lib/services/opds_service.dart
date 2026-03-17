import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:speedy_boy/core/logger.dart';
import 'package:xml/xml.dart';

const String _tag = 'opds_service';

// ── Data Models ──

class OpdsLink {
  const OpdsLink({required this.href, required this.type, this.rel});

  final String href;
  final String type;
  final String? rel;
}

class OpdsEntry {
  const OpdsEntry({
    required this.id,
    required this.title,
    this.author,
    this.coverUrl,
    this.links = const [],
    this.subsectionUrl,
  });

  final String id;
  final String title;
  final String? author;
  final String? coverUrl;
  final List<OpdsLink> links;

  /// URL to a detail OPDS page (rel=subsection) that contains acquisition links.
  final String? subsectionUrl;
}

class OpdsCatalog {
  const OpdsCatalog({
    this.entries = const [],
    this.totalResults = 0,
    this.nextUrl,
  });

  final List<OpdsEntry> entries;
  final int totalResults;
  final String? nextUrl;
}

// ── OPDS Service ──

class OpdsService {
  OpdsService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const String _baseUrl =
      'https://www.gutenberg.org/ebooks/search.opds/';

  /// Fetch catalog with optional search query and page number.
  Future<OpdsCatalog> fetchCatalog({String? query, int page = 1}) async {
    final uri = _buildUri(query: query, page: page);
    appLog(_tag, 'fetchCatalog start query="$query" page=$page');

    final response = await _client.get(uri).timeout(
          const Duration(seconds: 15),
        );

    if (response.statusCode != 200) {
      appLog(_tag, 'fetchCatalog failed status=${response.statusCode}');
      throw HttpException(
        'OPDS feed returned ${response.statusCode}',
        uri: uri,
      );
    }

    appLog(_tag, 'fetchCatalog parsing ${response.bodyBytes.length} bytes');
    final catalog = _parseOpdsFeed(response.body);
    appLog(_tag, 'fetchCatalog done entryCount=${catalog.entries.length}');
    return catalog;
  }

  /// Download a book file to the app documents directory.
  /// Returns the local file path on success.
  Future<String> downloadBook(OpdsEntry entry, {String? format}) async {
    OpdsLink? link = _getPreferredLink(entry, preferredType: format);

    // Gutenberg's search feed only has subsection links — follow to detail page.
    if (link == null && entry.subsectionUrl != null) {
      appLog(
        _tag,
        'download no acquisition links, fetching subsection title="${entry.title}" url=${entry.subsectionUrl}',
      );
      final detailCatalog = await _fetchAndParse(entry.subsectionUrl!);
      // Find the matching entry in the detail feed (usually only one).
      for (final detailEntry in detailCatalog.entries) {
        link = _getPreferredLink(detailEntry, preferredType: format);
        if (link != null) break;
      }
      // If detail feed had no entries but had top-level acquisition links,
      // parse them from the raw feed's link elements directly.
      if (link == null && detailCatalog.entries.isEmpty) {
        appLog(
          _tag,
          'download subsection had no entries title="${entry.title}"',
        );
      }
    }

    if (link == null) {
      throw Exception('No downloadable format found for "${entry.title}"');
    }

    final downloadUri = Uri.parse(link.href);
    final stopwatch = Stopwatch()..start();
    appLog(
      _tag,
      'download start title="${entry.title}" type="${link.type}" uri=$downloadUri',
    );

    try {
      final request = http.Request('GET', downloadUri);
      final response = await _client.send(request).timeout(
            const Duration(seconds: 120),
          );

      if (response.statusCode != 200) {
        appLog(
          _tag,
          'download failed title="${entry.title}" status=${response.statusCode} uri=$downloadUri',
        );
        throw HttpException(
          'Download failed with ${response.statusCode}',
          uri: downloadUri,
        );
      }

      final contentLength = response.contentLength;
      appLog(
        _tag,
        'download response title="${entry.title}" status=200 contentLength=${contentLength ?? -1}',
      );

      final dir = await getApplicationDocumentsDirectory();
      final booksDir = Directory('${dir.path}${Platform.pathSeparator}books');
      if (!booksDir.existsSync()) {
        booksDir.createSync(recursive: true);
      }

      final extension = _extensionForType(link.type);
      final sanitised = _sanitiseFilename(entry.title);
      final filePath =
          '${booksDir.path}${Platform.pathSeparator}$sanitised$extension';

      final file = File(filePath);
      final sink = file.openWrite();

      int downloadedBytes = 0;
      int nextProgressLogAt =
          512 * 1024; // Log every 512KB when size is unknown.
      int nextPercentLogAt = 10; // Log every 10% when content length is known.

      await for (final chunk in response.stream) {
        sink.add(chunk);
        downloadedBytes += chunk.length;

        if (contentLength != null && contentLength > 0) {
          final percent = (downloadedBytes * 100) ~/ contentLength;
          if (percent >= nextPercentLogAt) {
            appLog(
              _tag,
              'download progress title="${entry.title}" $percent% ($downloadedBytes/$contentLength bytes)',
            );
            nextPercentLogAt += 10;
          }
        } else if (downloadedBytes >= nextProgressLogAt) {
          appLog(
            _tag,
            'download progress title="${entry.title}" $downloadedBytes bytes',
          );
          nextProgressLogAt += 512 * 1024;
        }
      }

      await sink.close();

      stopwatch.stop();
      appLog(
        _tag,
        'download complete title="${entry.title}" bytes=$downloadedBytes ms=${stopwatch.elapsedMilliseconds} path=$filePath',
      );
      return filePath;
    } catch (e) {
      stopwatch.stop();
      appLog(
        _tag,
        'download exception title="${entry.title}" afterMs=${stopwatch.elapsedMilliseconds} error=$e',
      );
      rethrow;
    }
  }

  void dispose() {
    _client.close();
  }

  // ── Private helpers ──

  /// Fetch an OPDS feed URL and parse it. Used for following subsection links.
  Future<OpdsCatalog> _fetchAndParse(String url) async {
    final uri = Uri.parse(url);
    final response = await _client.get(uri).timeout(
          const Duration(seconds: 15),
        );
    if (response.statusCode != 200) {
      throw HttpException(
        'OPDS detail feed returned ${response.statusCode}',
        uri: uri,
      );
    }
    return _parseOpdsFeed(response.body);
  }

  Uri _buildUri({String? query, int page = 1}) {
    final params = <String, String>{};
    if (query != null && query.isNotEmpty) {
      params['query'] = query;
    }
    if (page > 1) {
      params['start_index'] = '${(page - 1) * 25 + 1}';
    }
    return Uri.parse(_baseUrl).replace(queryParameters: params);
  }

  OpdsCatalog _parseOpdsFeed(String body) {
    appLog(_tag, 'parseOpdsFeed start bodyLength=${body.length}');
    try {
      final document = XmlDocument.parse(body);
      final feed = document.rootElement;

      // Namespace-aware lookups.
      const atomNs = 'http://www.w3.org/2005/Atom';
      const dcNs = 'http://purl.org/dc/terms/';
      const opensearchNs = 'http://a9.com/-/spec/opensearch/1.1/';

      // Total results (OpenSearch).
      final totalResultsEl =
          feed.getElement('totalResults', namespace: opensearchNs) ??
              feed.getElement('opensearch:totalResults');
      final totalResults = int.tryParse(totalResultsEl?.innerText ?? '') ?? 0;

      // Next page link.
      String? nextUrl;
      for (final link in feed.findAllElements('link', namespace: atomNs)) {
        if (link.getAttribute('rel') == 'next') {
          final href = link.getAttribute('href');
          if (href != null) {
            nextUrl = href.startsWith('http')
                ? href
                : 'https://www.gutenberg.org$href';
          }
          break;
        }
      }

      // Entries.
      final entries = <OpdsEntry>[];
      for (final entryEl in feed.findAllElements('entry', namespace: atomNs)) {
        final id = entryEl.getElement('id', namespace: atomNs)?.innerText ?? '';
        final title =
            entryEl.getElement('title', namespace: atomNs)?.innerText ?? '';

        // Author — prefer <author><name>, fall back to <dcterms:creator>.
        final authorEl = entryEl.getElement('author', namespace: atomNs);
        final authorName =
            authorEl?.getElement('name', namespace: atomNs)?.innerText;
        final dcCreator = entryEl.getElement('creator', namespace: dcNs);
        final author = authorName ?? dcCreator?.innerText;

        // Cover image.
        String? coverUrl;
        String? subsectionUrl;
        final links = <OpdsLink>[];

        for (final linkEl
            in entryEl.findAllElements('link', namespace: atomNs)) {
          final href = linkEl.getAttribute('href') ?? '';
          final type = linkEl.getAttribute('type') ?? '';
          final rel = linkEl.getAttribute('rel');

          appLog(
            _tag,
            'parse link raw rel=$rel type=$type href=$href',
          );

          // Resolve relative URLs. data: URIs are embedded base64 and used directly.
          final resolvedHref = href.startsWith('http')
              ? href
              : href.startsWith('data:')
                  ? href
                  : 'https://www.gutenberg.org$href';

          if (rel == 'http://opds-spec.org/image' ||
              rel == 'http://opds-spec.org/image/thumbnail') {
            coverUrl ??= resolvedHref;
          }

          if (rel == 'http://opds-spec.org/acquisition' ||
              rel == 'http://opds-spec.org/acquisition/open-access') {
            links.add(OpdsLink(href: resolvedHref, type: type, rel: rel));
            appLog(
              _tag,
              'parse acquisition title="$title" acquired type=$type',
            );
          }

          // Capture subsection link (detail page) for two-step download.
          if (rel == 'subsection' && type.contains('atom+xml')) {
            subsectionUrl ??= resolvedHref;
          }
        }

        appLog(
          _tag,
          'parse entry title="$title" linkCount=${links.length} coverUrl=${coverUrl != null}',
        );

        if (title.isNotEmpty) {
          entries.add(OpdsEntry(
            id: id,
            title: title,
            author: author,
            coverUrl: coverUrl,
            links: links,
            subsectionUrl: subsectionUrl,
          ));
        }
      }

      final result = OpdsCatalog(
        entries: entries,
        totalResults: totalResults,
        nextUrl: nextUrl,
      );
      appLog(_tag, 'parseOpdsFeed done entryCount=${result.entries.length}');
      return result;
    } catch (e) {
      appLog(_tag, 'parseOpdsFeed exception error=$e');
      rethrow;
    }
  }

  /// Pick the best acquisition link (prefer PDF, then EPUB).
  OpdsLink? _getPreferredLink(OpdsEntry entry, {String? preferredType}) {
    if (entry.links.isEmpty) return null;

    if (preferredType != null) {
      final match =
          entry.links.where((l) => l.type.contains(preferredType)).firstOrNull;
      if (match != null) return match;
    }

    // Prefer PDF for direct reading support.
    final pdf = entry.links.where((l) => l.type.contains('pdf')).firstOrNull;
    if (pdf != null) return pdf;

    // Fall back to EPUB.
    final epub = entry.links.where((l) => l.type.contains('epub')).firstOrNull;
    if (epub != null) return epub;

    // Last resort: first available link.
    return entry.links.first;
  }

  String _extensionForType(String mimeType) {
    if (mimeType.contains('pdf')) return '.pdf';
    if (mimeType.contains('epub')) return '.epub';
    return '.pdf';
  }

  /// Remove characters that are unsafe for file names.
  String _sanitiseFilename(String name) {
    return name
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .substring(0, name.length > 80 ? 80 : name.length)
        .trim();
  }
}

// ── Riverpod providers ──

final opdsServiceProvider = Provider<OpdsService>((ref) {
  final service = OpdsService();
  ref.onDispose(service.dispose);
  return service;
});

final opdsCatalogProvider =
    FutureProvider.family<OpdsCatalog, ({String? query, int page})>(
  (ref, params) {
    final service = ref.watch(opdsServiceProvider);
    return service.fetchCatalog(query: params.query, page: params.page);
  },
);
