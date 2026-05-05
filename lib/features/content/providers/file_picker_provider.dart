import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:runthru/features/content/services/content_normaliser.dart';
import 'package:runthru/services/epub_extractor.dart';
import 'package:runthru/services/models.dart';
import 'package:runthru/services/pdf_extractor.dart';

part 'file_picker_provider.g.dart';

/// Progress state for the file picker ingestion pipeline.
sealed class FilePickerState {
  /// Idle — no file operation in progress.
  const factory FilePickerState.idle() = FilePickerIdle;

  /// File picker dialog is open.
  const factory FilePickerState.picking() = FilePickerPicking;

  /// Extracting content from the selected file.
  const factory FilePickerState.extracting({
    required String fileName,
    double progress,
  }) = FilePickerExtracting;

  /// Extraction completed successfully.
  const factory FilePickerState.done({
    required String fileName,
    required ExtractedDocument document,
  }) = FilePickerDone;

  /// An error occurred during extraction.
  const factory FilePickerState.error({required String message}) =
      FilePickerError;
}

/// Idle — no file operation in progress.
class FilePickerIdle implements FilePickerState {
  /// Creates an idle state.
  const FilePickerIdle();
}

/// File picker dialog is open.
class FilePickerPicking implements FilePickerState {
  /// Creates a picking state.
  const FilePickerPicking();
}

/// Extracting content from the selected file.
class FilePickerExtracting implements FilePickerState {
  /// Creates an extracting state.
  const FilePickerExtracting({required this.fileName, this.progress = 0.0});

  /// The name of the file being extracted.
  final String fileName;

  /// Progress from 0.0 to 1.0.
  final double progress;
}

/// Extraction completed successfully.
class FilePickerDone implements FilePickerState {
  /// Creates a done state.
  const FilePickerDone({required this.fileName, required this.document});

  /// The name of the extracted file.
  final String fileName;

  /// The extracted document ready for reading.
  final ExtractedDocument document;
}

/// An error occurred during extraction.
class FilePickerError implements FilePickerState {
  /// Creates an error state.
  const FilePickerError({required this.message});

  /// Human-readable error description.
  final String message;
}

/// Supported file extensions for the file picker.
const List<String> _supportedExtensions = ['pdf', 'epub', 'txt', 'md', 'html'];

/// Manages file picking and content extraction.
///
/// Uses the `file_picker` package to open the system file picker filtered
/// to supported formats. Routes the selected file to the appropriate
/// extractor and reports progress via provider state.
///
/// Files are copied to app-private storage before extraction.
/// Content stays on-device only — no cloud upload.
@riverpod
class FilePickerNotifier extends _$FilePickerNotifier {
  @override
  FilePickerState build() {
    return const FilePickerState.idle();
  }

  /// Opens the system file picker and processes the selected file.
  Future<void> pickAndExtract() async {
    state = const FilePickerState.picking();

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: _supportedExtensions,
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) {
        state = const FilePickerState.idle();
        return;
      }

      final pickedFile = result.files.first;
      final sourcePath = pickedFile.path;
      final fileName = pickedFile.name;

      if (sourcePath == null) {
        state = const FilePickerState.error(
          message: 'Could not access the selected file.',
        );
        return;
      }

      state = FilePickerState.extracting(fileName: fileName);

      // Copy to app-private storage (privacy: don't retain original paths).
      final appDir = await getApplicationDocumentsDirectory();
      final importDir = Directory('${appDir.path}/imports');
      if (!importDir.existsSync()) {
        importDir.createSync(recursive: true);
      }
      final privatePath = '${importDir.path}/$fileName';
      await File(sourcePath).copy(privatePath);

      // Route to the appropriate extractor based on file extension.
      final ext = fileName.split('.').last.toLowerCase();
      final document = await _extractFile(privatePath, ext, fileName);

      state = FilePickerState.done(fileName: fileName, document: document);
    } on Exception catch (e) {
      state = FilePickerState.error(message: e.toString());
    }
  }

  /// Resets state back to idle.
  void clear() {
    state = const FilePickerState.idle();
  }

  Future<ExtractedDocument> _extractFile(
    String filePath,
    String extension,
    String fileName,
  ) async {
    switch (extension) {
      case 'pdf':
        return extractPdfInIsolate(filePath);
      case 'epub':
        return extractEpubInIsolate(filePath);
      case 'txt':
        final txtContent = await File(filePath).readAsString();
        return ContentNormaliser.normalise(txtContent, ContentType.plainText);
      case 'md':
        final mdContent = await File(filePath).readAsString();
        return ContentNormaliser.normalise(mdContent, ContentType.markdown);
      case 'html':
        final htmlContent = await File(filePath).readAsString();
        return ContentNormaliser.normalise(htmlContent, ContentType.html);
      default:
        throw UnsupportedError('Unsupported file format: $extension');
    }
  }
}
