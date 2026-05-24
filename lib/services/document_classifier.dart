import 'dart:io';

/// Supported local document families for RunThru ingestion.
enum DocumentKind {
  /// Portable Document Format, handled by pdfrx/pdfium.
  pdf,

  /// EPUB ZIP-based book, handled by RunThru's EPUB extractor.
  epub,

  /// A file extension or signature RunThru does not read as a book.
  unsupported,
}

/// Lightweight document classifier used before routing to extractors/renderers.
class DocumentClassifier {
  DocumentClassifier._();

  /// Returns the best document kind for [path] using extension plus a small
  /// header check when the file exists locally.
  static Future<DocumentKind> classifyPath(String path) async {
    final extensionKind = kindFromExtension(path);
    if (extensionKind == DocumentKind.unsupported) return extensionKind;

    final file = File(path);
    if (!await file.exists()) return extensionKind;

    final signatureKind = await kindFromSignature(file);
    if (signatureKind == DocumentKind.unsupported) return extensionKind;
    return signatureKind;
  }

  /// Classifies a file by extension only.
  static DocumentKind kindFromExtension(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.pdf')) return DocumentKind.pdf;
    if (lower.endsWith('.epub')) return DocumentKind.epub;
    return DocumentKind.unsupported;
  }

  /// Classifies a file by a minimal magic-header/signature read.
  static Future<DocumentKind> kindFromSignature(File file) async {
    final raf = await file.open();
    try {
      final length = await raf.length();
      final bytes = await raf.read(length < 58 ? length : 58);
      return kindFromBytes(bytes);
    } finally {
      await raf.close();
    }
  }

  /// Classifies raw bytes by known book signatures.
  static DocumentKind kindFromBytes(List<int> bytes) {
    if (bytes.length >= 5 &&
        bytes[0] == 0x25 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x44 &&
        bytes[3] == 0x46 &&
        bytes[4] == 0x2d) {
      return DocumentKind.pdf;
    }

    // EPUB is a ZIP whose first stored entry is usually the uncompressed
    // "mimetype" file containing application/epub+zip.
    final asLatin1 = String.fromCharCodes(bytes);
    if (bytes.length >= 4 &&
        bytes[0] == 0x50 &&
        bytes[1] == 0x4b &&
        bytes[2] == 0x03 &&
        bytes[3] == 0x04 &&
        asLatin1.contains('application/epub+zip')) {
      return DocumentKind.epub;
    }

    return DocumentKind.unsupported;
  }
}
