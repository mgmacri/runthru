import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/services/analytics_service.dart';
import 'package:runthru/store/analytics_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('AnalyticsService', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test(
      'calculates reading-time totals without changing persisted sessions',
      () async {
        final service = AnalyticsService();
        final now = DateTime.now();
        final todayStart = DateTime(now.year, now.month, now.day, 9);
        final yesterdayStart = todayStart.subtract(const Duration(days: 1));

        await service.saveSession(
          ReadingSession(
            startTime: yesterdayStart,
            endTime: yesterdayStart.add(const Duration(minutes: 30)),
            wordsRead: 1200,
            avgWpm: 240,
            filePath: 'yesterday.pdf',
          ),
        );
        await service.saveSession(
          ReadingSession(
            startTime: todayStart,
            endTime: todayStart.add(const Duration(minutes: 15)),
            wordsRead: 600,
            avgWpm: 240,
            filePath: 'today.pdf',
          ),
        );

        final stats = await service.calculateStats();

        expect(stats.totalReadingTime, const Duration(minutes: 45));
        expect(stats.todayReadingTime, const Duration(minutes: 15));
        expect(stats.weekReadingTime, const Duration(minutes: 45));
        expect(stats.readingTimeHistory, hasLength(30));
        expect(
          stats.readingTimeHistory.where((entry) => entry.hasReading),
          hasLength(2),
        );
      },
    );
  });
}
