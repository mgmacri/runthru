import 'dart:io';
import 'dart:isolate';

import 'package:speedy_boy/services/models.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Top-level function for Isolate.run() — extracts text from PDF.
/// Must be top-level or static (Dart Isolate requirement).
ExtractedDocument pdfExtract(String filePath) {
  final file = File(filePath);
  if (!file.existsSync()) {
    throw FileSystemException('File not found', filePath);
  }

  final bytes = file.readAsBytesSync();
  final document = PdfDocument(inputBytes: bytes);

  final allText = StringBuffer();
  for (var i = 0; i < document.pages.count; i++) {
    final extractor = PdfTextExtractor(document);
    final text = extractor.extractText(startPageIndex: i);
    allText.write(text);
    allText.write(' ');
  }
  document.dispose();

  final rawText = allText.toString().trim();
  if (rawText.isEmpty) {
    throw const UnsupportedPdfError(
      'Image-only PDF — no extractable text',
    );
  }

  return _parseToSentences(rawText);
}

/// Runs PDF extraction in a separate Dart Isolate.
Future<ExtractedDocument> extractPdfInIsolate(
  String filePath,
) async {
  return Isolate.run(() => pdfExtract(filePath));
}

/// Splits raw text into sentences, each with its word list.
ExtractedDocument _parseToSentences(String text) {
  // Split on sentence-ending punctuation followed by whitespace
  final sentencePattern = RegExp(
    r'(?<=[.!?])\s+',
  );
  final rawSentences = text.split(sentencePattern);
  final sentences = <Sentence>[];

  for (final raw in rawSentences) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) continue;

    final words =
        trimmed.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isNotEmpty) {
      sentences.add(Sentence(words: words));
    }
  }

  return ExtractedDocument(sentences: sentences);
}
