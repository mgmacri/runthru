import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/screens/analytics_screen.dart';
import 'package:runthru/services/analytics_service.dart';
import 'package:runthru/store/analytics_models.dart';

class _FakeAnalyticsService extends AnalyticsService {
  _FakeAnalyticsService(this.stats);

  final ReadingStats stats;

  @override
  Future<ReadingStats> calculateStats() async => stats;
}

Widget _harness(ReadingStats stats) {
  return ProviderScope(
    overrides: [
      analyticsServiceProvider.overrideWithValue(_FakeAnalyticsService(stats)),
    ],
    child: const MaterialApp(home: AnalyticsScreen()),
  );
}

void main() {
  group('AnalyticsScreen', () {
    testWidgets(
      'shows time, streak, and encouragement instead of speed stats',
      (tester) async {
        final today = DateTime.now();
        final todayDate = DateTime(today.year, today.month, today.day);

        await tester.pumpWidget(
          _harness(
            ReadingStats(
              totalSessions: 3,
              totalWordsRead: 2400,
              avgWpm: 260,
              streak: 2,
              totalReadingTime: const Duration(minutes: 45),
              todayReadingTime: const Duration(minutes: 12),
              weekReadingTime: const Duration(minutes: 45),
              readingTimeHistory: [
                for (int i = 6; i >= 0; i--)
                  DailyReadingTime(
                    date: todayDate.subtract(Duration(days: i)),
                    readingTime: i.isEven
                        ? const Duration(minutes: 10)
                        : Duration.zero,
                  ),
              ],
            ),
          ),
        );
        await tester.pump();

        expect(find.text('Reading Wins'), findsOneWidget);
        expect(find.text('You read today'), findsOneWidget);
        expect(find.text('Reading time'), findsOneWidget);
        expect(find.text('About 45 min'), findsWidgets);
        expect(find.text('Streak'), findsOneWidget);
        expect(find.text('2 days'), findsOneWidget);

        await tester.drag(find.byType(ListView), const Offset(0, -500));
        await tester.pump();

        expect(find.text('Worth feeling good about'), findsOneWidget);

        expect(find.text('Average WPM'), findsNothing);
        expect(find.text('WPM Over Time'), findsNothing);
        expect(find.text('Words'), findsNothing);
        expect(find.text('Sessions'), findsNothing);
        expect(find.text('2400'), findsNothing);
        expect(find.text('260'), findsNothing);
      },
    );

    testWidgets('empty state uses encouraging non-speed copy', (tester) async {
      await tester.pumpWidget(_harness(const ReadingStats()));
      await tester.pump();

      expect(find.text('Nothing to measure yet'), findsOneWidget);
      expect(
        find.text(
          'Read something you want to get through, then come back here.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('speed'), findsNothing);
      expect(find.textContaining('WPM'), findsNothing);
    });
  });
}
