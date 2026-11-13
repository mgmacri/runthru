import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/features/content/models/shared_content.dart';
import 'package:runthru/features/content/providers/share_intent_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ShareIntentState> ingest(SharedContent content) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(shareIntentProvider.notifier).ingest(content);
    return container.read(shareIntentProvider);
  }

  group('ShareIntent', () {
    test('shared text is ready to read', () async {
      final state = await ingest(
        SharedContent.text('A short note. It has two sentences.'),
      );

      expect(state, isA<ShareIntentDone>());
      final words = (state as ShareIntentDone).document.sentences
          .expand((s) => s.words)
          .toList();
      expect(words.first, 'A');
      expect(words.last, 'sentences.');
    });
  });

  group('ShareIntent: what the reader is told while it opens', () {
    test(
      'a link and a file are announced; text is not, it is there at once',
      () {
        // Nothing was shown at all while a link loaded, for as long as its
        // site took.
        expect(
          shareProgressMessage(SharedContent.url('https://example.org/a')),
          'Opening the link you shared…',
        );
        expect(
          shareProgressMessage(SharedContent.pdfFile('/tmp/a.pdf')),
          'Opening the file you shared…',
        );
        expect(
          shareProgressMessage(SharedContent.epubFile('/tmp/a.epub')),
          'Opening the file you shared…',
        );
        expect(shareProgressMessage(SharedContent.text('Some words.')), isNull);
      },
    );
  });

  group('ShareIntent: what the reader is told when sharing fails', () {
    test('a link to a chat app says what to do', () async {
      final state = await ingest(
        SharedContent.url('https://chatgpt.com/share/abc'),
      );

      expect(state, isA<ShareIntentError>());
      final message = (state as ShareIntentError).message;
      expect(
        message,
        startsWith('This app shared a link to the conversation, not the text.'),
      );
      expect(message, isNot(contains('Exception')));
    });

    test('a link that is not a web address', () async {
      final state = await ingest(
        SharedContent.url('ftp://example.com/file.txt'),
      );

      expect(state, isA<ShareIntentError>());
      expect(
        (state as ShareIntentError).message,
        startsWith('Only web links can be fetched.'),
      );
    });

    test(
      'a file that cannot be opened is not described by its error',
      () async {
        final state = await ingest(
          SharedContent.pdfFile('/nowhere/missing.pdf'),
        );

        expect(state, isA<ShareIntentError>());
        final message = (state as ShareIntentError).message;
        // The error's own text names its type and the file's path.
        expect(message, isNot(contains('Exception')));
        expect(message, isNot(contains('/nowhere')));
        expect(message, startsWith('RunThru could not open what was shared.'));
      },
    );
  });
}
