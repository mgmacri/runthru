import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runthru/core/document_title.dart';
import 'package:runthru/services/epub_extractor.dart';

/// Display title for a local document: the EPUB's metadata title when it
/// has one, otherwise a cleaned-up file name. Cached for the app session.
final documentTitleProvider = FutureProvider.family<String, String>((
  ref,
  filePath,
) async {
  ref.keepAlive();
  if (filePath.toLowerCase().endsWith('.epub')) {
    final title = await epubTitle(filePath);
    if (title != null) return title;
  }
  return prettyFileTitle(filePath);
});
