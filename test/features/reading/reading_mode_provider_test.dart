import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runthru/features/reading/providers/reading_mode_provider.dart';

void main() {
  group('ReadingModeNotifier', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('swipe-up order cycles through the available reading modes', () {
      final notifier = container.read(readingModeNotifierProvider.notifier);

      expect(
        container.read(readingModeNotifierProvider),
        ReadingMode.singleWord,
      );

      notifier.cycleMode();
      expect(container.read(readingModeNotifierProvider), ReadingMode.sentence);

      notifier.cycleMode();
      expect(
        container.read(readingModeNotifierProvider),
        ReadingMode.paragraph,
      );

      notifier.cycleMode();
      expect(container.read(readingModeNotifierProvider), ReadingMode.fullPage);

      notifier.cycleMode();
      expect(
        container.read(readingModeNotifierProvider),
        ReadingMode.singleWord,
      );
    });

    test('swipe-down order reverses and wraps', () {
      final notifier = container.read(readingModeNotifierProvider.notifier);

      notifier.setMode(ReadingMode.sentence);
      notifier.cycleModeReverse();
      expect(
        container.read(readingModeNotifierProvider),
        ReadingMode.singleWord,
      );

      notifier.cycleModeReverse();
      expect(container.read(readingModeNotifierProvider), ReadingMode.fullPage);
    });

    test('every reading mode is offered, Sentence included', () {
      expect(availableReadingModes, ReadingMode.values);
    });

    test('parses old and invalid persisted names safely', () {
      expect(ReadingModeX.parse('rsvp'), ReadingMode.singleWord);
      expect(ReadingModeX.parse('sentence'), ReadingMode.sentence);
      expect(ReadingModeX.parse('missing'), ReadingMode.singleWord);
      expect(ReadingModeX.parse(null), ReadingMode.singleWord);
    });
  });
}
