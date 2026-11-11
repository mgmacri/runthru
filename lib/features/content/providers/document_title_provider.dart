import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runthru/core/document_title.dart';
import 'package:runthru/services/content_store/content_store.dart';
import 'package:runthru/services/epub_extractor.dart';
import 'package:runthru/services/models.dart';
import 'package:runthru/services/preprocessing_queue.dart';

/// What a local document says about itself, for library rows and the reader.
class DocumentInfo {
  /// Creates document info.
  const DocumentInfo({required this.title, this.author});

  /// Display title: the file's own title when it has one, otherwise a
  /// cleaned-up file name.
  final String title;

  /// The author the file names, if any.
  final String? author;
}

/// Title and author of a local document: an EPUB's package metadata when it
/// has some, otherwise a cleaned-up file name. One read of the file's
/// package per app session.
final documentInfoProvider = FutureProvider.family<DocumentInfo, String>((
  ref,
  filePath,
) async {
  ref.keepAlive();
  if (filePath.toLowerCase().endsWith('.epub')) {
    final info = await epubInfo(filePath);
    if (info != null) {
      return DocumentInfo(
        title: info.title ?? prettyFileTitle(filePath),
        author: info.author,
      );
    }
  }
  return DocumentInfo(title: prettyFileTitle(filePath));
});

/// Display title for a local document: the EPUB's metadata title when it
/// has one, otherwise a cleaned-up file name. Cached for the app session.
final documentTitleProvider = FutureProvider.family<String, String>((
  ref,
  filePath,
) async {
  ref.keepAlive();
  return (await ref.watch(documentInfoProvider(filePath).future)).title;
});

/// Number of words in a local document once its text has been extracted,
/// or null while that is not known. Read from the content store's manifest:
/// no text is loaded.
final documentWordCountProvider = FutureProvider.family<int?, String>((
  ref,
  filePath,
) async {
  // Looked up again whenever the queue touches the file's entry (entries
  // are replaced, never changed in place): the count exists once extraction
  // has finished, and changes when a book is extracted again by a newer
  // build while the app is open.
  final entry = ref.watch(
    preprocessingQueueProvider.select((entries) => entries[filePath]),
  );
  if (entry?.status != PdfStatus.ready) return null;
  final hash = ref
      .read(preprocessingQueueProvider.notifier)
      .contentHashOf(filePath);
  if (hash == null) return null;
  final metadata = await ref.read(contentStoreProvider).getMetadata(hash);
  final words = metadata?.totalWords ?? 0;
  return words > 0 ? words : null;
});
