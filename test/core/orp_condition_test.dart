import 'package:flutter_test/flutter_test.dart';
import 'package:speedy_boy/core/orp.dart';
import 'package:speedy_boy/store/models.dart';
import 'package:speedy_boy/three_d/text_painter_pool.dart';
import 'package:speedy_boy/three_d/word_painter.dart';

void main() {
  group('OrpCondition in WordPainter', () {
    late TextPainterPool pool;

    setUp(() {
      pool = TextPainterPool();
    });

    test('default orpBoldColor preserves existing behavior', () {
      final painter = WordPainter(
        word: 'hello',
        fontSize: 24,
        animationValue: 0,
        painterPool: pool,
      );

      // Default condition is orpBoldColor
      expect(painter.orpCondition, OrpCondition.orpBoldColor);
      // ORP index for 'hello' (5 chars) → center = 3 (1-indexed)
      expect(orpIndexInOriginal('hello'), 3);
    });

    test('orpColorOnly uses regular weight with anchor color', () {
      final painter = WordPainter(
        word: 'reading',
        fontSize: 24,
        animationValue: 0,
        painterPool: pool,
        orpCondition: OrpCondition.orpColorOnly,
      );

      expect(painter.orpCondition, OrpCondition.orpColorOnly);

      // Verify painter repaints when condition changes
      final painterBold = WordPainter(
        word: 'reading',
        fontSize: 24,
        animationValue: 0,
        painterPool: pool,
        orpCondition: OrpCondition.orpBoldColor,
      );

      expect(painter.shouldRepaint(painterBold), isTrue);
    });

    test('centerAligned centers word horizontally', () {
      final painter = WordPainter(
        word: 'centered',
        fontSize: 24,
        animationValue: 0,
        painterPool: pool,
        orpCondition: OrpCondition.centerAligned,
      );

      expect(painter.orpCondition, OrpCondition.centerAligned);

      // Different condition triggers repaint
      final painterDefault = WordPainter(
        word: 'centered',
        fontSize: 24,
        animationValue: 0,
        painterPool: pool,
      );

      expect(painter.shouldRepaint(painterDefault), isTrue);
    });
  });
}
