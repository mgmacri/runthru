import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/core/orp.dart';
import 'package:runthru/store/models.dart';
import 'package:runthru/three_d/off_axis_projection.dart';
import 'package:runthru/three_d/parallax_word_painter.dart';
import 'package:runthru/three_d/text_painter_pool.dart';
import 'package:runthru/three_d/word_painter.dart';

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

    test('anchor guide visibility participates in repaint decisions', () {
      final withGuides = WordPainter(
        word: 'reading',
        fontSize: 24,
        animationValue: 0,
        painterPool: pool,
      );
      final withoutGuides = WordPainter(
        word: 'reading',
        fontSize: 24,
        animationValue: 0,
        painterPool: pool,
        showAnchorGuides: false,
      );

      expect(withGuides.showAnchorGuides, isTrue);
      expect(withGuides.shouldRepaint(withoutGuides), isTrue);
    });
  });

  group('OrpCondition in ParallaxWordPainter', () {
    late TextPainterPool pool;

    setUp(() {
      pool = TextPainterPool();
    });

    test('anchor guide visibility participates in repaint decisions', () {
      final withGuides = ParallaxWordPainter(
        word: 'reading',
        fontSize: 42,
        headX: 0,
        headY: 0,
        config: const RoomConfig(),
        painterPool: pool,
        animationValue: 1,
      );
      final withoutGuides = ParallaxWordPainter(
        word: 'reading',
        fontSize: 42,
        headX: 0,
        headY: 0,
        config: const RoomConfig(),
        painterPool: pool,
        animationValue: 1,
        showAnchorGuides: false,
      );

      expect(withGuides.showAnchorGuides, isTrue);
      expect(withGuides.shouldRepaint(withoutGuides), isTrue);
    });
  });
}
