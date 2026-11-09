import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/core/word_timer.dart';

/// Phase 7 of the scale overhaul: model-annotated difficulty reaches the
/// pacing path only when attached — the tick logic itself is untouched.
void main() {
  group('WordTimer difficulty hook', () {
    test('without a difficulty source pacing is unchanged', () {
      fakeAsync((async) {
        final timer = WordTimerNotifier();
        timer.loadDocument(10);
        timer.setWpm(600); // 100ms interval
        timer.play();

        async.elapse(const Duration(seconds: 3));
        expect(timer.state.currentIndex, 9, reason: 'document finished');
        timer.dispose();
      });
    });

    test('difficulty multiplier slows annotated words', () {
      fakeAsync((async) {
        final timer = WordTimerNotifier();
        timer.loadDocument(10);
        timer.setWpm(600); // 100ms base interval
        // Every word annotated as hard: dwell 3x longer.
        timer.attachDifficultySource((index) => 3.0);
        timer.play();

        // After ~1s at 3x intervals (~300ms/word, warmup makes it slower
        // still), far fewer words advanced than the unannotated run.
        async.elapse(const Duration(milliseconds: 1050));
        expect(timer.state.currentIndex, lessThan(5));
        timer.dispose();
      });
    });

    test('null annotations leave individual words untouched', () {
      fakeAsync((async) {
        final timer = WordTimerNotifier();
        timer.loadDocument(10);
        timer.setWpm(600);
        // Model annotated nothing — callback returns null everywhere.
        timer.attachDifficultySource((index) => null);
        timer.play();

        async.elapse(const Duration(seconds: 3));
        expect(timer.state.currentIndex, 9, reason: 'document finished');
        timer.dispose();
      });
    });

    test('loadDocument clears the previous difficulty source', () {
      fakeAsync((async) {
        final timer = WordTimerNotifier();
        timer.loadDocument(10);
        timer.setWpm(600);
        timer.attachDifficultySource((index) => 3.0);

        // New document — annotations from the old book must not leak.
        timer.loadDocument(10);
        timer.setWpm(600); // loadDocument resets wpm to its default
        timer.play();
        async.elapse(const Duration(seconds: 3));
        expect(timer.state.currentIndex, 9, reason: 'document finished');
        timer.dispose();
      });
    });
  });
}
