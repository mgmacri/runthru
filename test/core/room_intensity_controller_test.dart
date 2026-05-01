import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/core/room_intensity_controller.dart';
import 'package:runthru/design/design.dart';

void main() {
  group('RoomIntensityController', () {
    late RoomIntensityController controller;
    late DateTime fakeNow;

    setUp(() {
      fakeNow = DateTime(2025, 1, 1, 12, 0, 0);
      controller = RoomIntensityController(clock: () => fakeNow);
    });

    test('empty window returns smoothedDifficulty 0.5', () {
      expect(controller.smoothedDifficulty, 0.5);
    });

    test('window fills with first 5 sentences', () {
      for (var i = 0; i < 5; i++) {
        controller.onSentenceComplete(6.0);
      }
      expect(controller.windowSize, 5);
      expect(controller.smoothedDifficulty, 6.0);
    });

    test('window rolls after exceeding windowSize', () {
      // Fill window to capacity
      for (var i = 0; i < RunThruTiming.roomDifficultyWindowSize; i++) {
        controller.onSentenceComplete(5.0);
      }
      expect(controller.windowSize, RunThruTiming.roomDifficultyWindowSize);

      // Add one more — oldest should be evicted
      controller.onSentenceComplete(10.0);
      expect(controller.windowSize, RunThruTiming.roomDifficultyWindowSize);
      // Average: (5+5+5+5+10)/5 = 6.0
      expect(controller.smoothedDifficulty, 6.0);
    });

    test('smoothedDifficulty computes running average', () {
      controller.onSentenceComplete(2.0);
      controller.onSentenceComplete(4.0);
      controller.onSentenceComplete(6.0);
      expect(controller.smoothedDifficulty, 4.0);
    });

    test('high difficulty triggers minimal intensity', () {
      // Push average to >= 9.0
      for (var i = 0; i < 5; i++) {
        controller.onSentenceComplete(9.0);
      }
      expect(controller.level, RoomIntensityLevel.minimal);
    });

    test('low difficulty triggers rich intensity', () {
      // Push average to <= 4.0
      for (var i = 0; i < 5; i++) {
        controller.onSentenceComplete(4.0);
      }
      expect(controller.level, RoomIntensityLevel.rich);
    });

    test('moderate difficulty stays moderate', () {
      for (var i = 0; i < 5; i++) {
        controller.onSentenceComplete(6.0);
      }
      expect(controller.level, RoomIntensityLevel.moderate);
    });

    test('boundary: 8.9 average stays moderate', () {
      for (var i = 0; i < 5; i++) {
        controller.onSentenceComplete(8.9);
      }
      expect(controller.level, RoomIntensityLevel.moderate);
    });

    test('boundary: 4.1 average stays moderate', () {
      for (var i = 0; i < 5; i++) {
        controller.onSentenceComplete(4.1);
      }
      expect(controller.level, RoomIntensityLevel.moderate);
    });

    test('hysteresis blocks transition within hold period', () {
      // Trigger transition to rich
      for (var i = 0; i < 5; i++) {
        controller.onSentenceComplete(4.0);
      }
      expect(controller.level, RoomIntensityLevel.rich);

      // Advance time by less than hysteresis hold
      fakeNow = fakeNow.add(
        const Duration(seconds: RunThruTiming.roomHysteresisHoldSeconds - 1),
      );

      // Try to transition to minimal — should be blocked
      for (var i = 0; i < 5; i++) {
        controller.onSentenceComplete(10.0);
      }
      expect(controller.level, RoomIntensityLevel.rich);
    });

    test('hysteresis allows transition after hold period', () {
      // Trigger transition to rich
      for (var i = 0; i < 5; i++) {
        controller.onSentenceComplete(4.0);
      }
      expect(controller.level, RoomIntensityLevel.rich);

      // Advance time past hysteresis hold
      fakeNow = fakeNow.add(
        const Duration(seconds: RunThruTiming.roomHysteresisHoldSeconds),
      );

      // Use value high enough that first addition pushes avg ≥ 9.0
      // Window: [4,4,4,4,30] → avg = 9.2 → minimal directly
      controller.onSentenceComplete(30.0);
      expect(controller.level, RoomIntensityLevel.minimal);
    });

    test('single spike does not change level', () {
      // Fill with moderate values
      for (var i = 0; i < 4; i++) {
        controller.onSentenceComplete(5.0);
      }
      // One extreme spike — average (5+5+5+5+10)/5 = 6.0 still moderate
      controller.onSentenceComplete(10.0);
      expect(controller.level, RoomIntensityLevel.moderate);
    });

    test('reset clears all state', () {
      // Establish some state
      for (var i = 0; i < 5; i++) {
        controller.onSentenceComplete(9.0);
      }
      expect(controller.level, RoomIntensityLevel.minimal);

      controller.reset();

      expect(controller.level, RoomIntensityLevel.moderate);
      expect(controller.smoothedDifficulty, 0.5);
      expect(controller.windowSize, 0);
    });
  });
}
