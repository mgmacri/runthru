import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:runthru/store/analytics_models.dart';

/// Service for persisting and querying reading analytics.
///
/// Stores sessions as JSON in SharedPreferences, capped at [_maxSessions]
/// to prevent storage bloat.
class AnalyticsService {
  static const _sessionsKey = 'reading_sessions';
  static const _maxSessions = 1000;

  Future<List<ReadingSession>> getSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_sessionsKey);
    if (raw == null) return [];

    try {
      final list = jsonDecode(raw) as List<Object?>;
      return list
          .whereType<Map<String, Object?>>()
          .map(ReadingSession.fromJson)
          .toList();
    } on Object {
      return [];
    }
  }

  Future<void> saveSession(ReadingSession session) async {
    // Skip sessions with no words read.
    if (session.wordsRead <= 0) return;

    final sessions = await getSessions();
    sessions.add(session);

    // Trim to max size, keeping the most recent.
    while (sessions.length > _maxSessions) {
      sessions.removeAt(0);
    }

    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(sessions.map((s) => s.toJson()).toList());
    await prefs.setString(_sessionsKey, json);
  }

  Future<ReadingStats> calculateStats() async {
    final sessions = await getSessions();
    if (sessions.isEmpty) return const ReadingStats();

    final totalWords =
        sessions.fold<int>(0, (sum, s) => sum + s.wordsRead);
    final totalWpmWeighted =
        sessions.fold<double>(0, (sum, s) => sum + s.avgWpm * s.wordsRead);
    final avgWpm = totalWords > 0 ? totalWpmWeighted / totalWords : 0.0;

    return ReadingStats(
      totalSessions: sessions.length,
      totalWordsRead: totalWords,
      avgWpm: avgWpm,
      streak: _calculateStreak(sessions),
      wpmHistory: _aggregateByDay(sessions),
    );
  }

  Future<void> clearAllData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionsKey);
  }

  /// Calculate consecutive days with at least one session ending today.
  int _calculateStreak(List<ReadingSession> sessions) {
    if (sessions.isEmpty) return 0;

    // Collect unique dates (local time, date only).
    final dates = sessions
        .map((s) {
          final t = s.startTime.toLocal();
          return DateTime(t.year, t.month, t.day);
        })
        .toSet()
        .toList()
      ..sort();

    if (dates.isEmpty) return 0;

    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final yesterday = todayDate.subtract(const Duration(days: 1));

    // Streak must include today or yesterday.
    if (dates.last != todayDate && dates.last != yesterday) return 0;

    int streak = 1;
    for (int i = dates.length - 1; i > 0; i--) {
      final diff = dates[i].difference(dates[i - 1]).inDays;
      if (diff == 1) {
        streak++;
      } else {
        break;
      }
    }
    return streak;
  }

  /// Aggregate sessions by day for the last 30 days.
  List<DailyWpm> _aggregateByDay(List<ReadingSession> sessions) {
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final cutoff = todayDate.subtract(const Duration(days: 29));

    // Group by local date.
    final Map<DateTime, List<ReadingSession>> grouped = {};
    for (final session in sessions) {
      final t = session.startTime.toLocal();
      final dateKey = DateTime(t.year, t.month, t.day);
      if (dateKey.isBefore(cutoff)) continue;
      grouped.putIfAbsent(dateKey, () => []).add(session);
    }

    // Build 30-day list (gaps get no entry — chart will show gaps).
    final result = <DailyWpm>[];
    for (int i = 0; i < 30; i++) {
      final date = cutoff.add(Duration(days: i));
      final daySessions = grouped[date];
      if (daySessions != null && daySessions.isNotEmpty) {
        final totalWords =
            daySessions.fold<int>(0, (sum, s) => sum + s.wordsRead);
        final totalWpmWeighted = daySessions.fold<double>(
            0, (sum, s) => sum + s.avgWpm * s.wordsRead);
        final avg = totalWords > 0 ? totalWpmWeighted / totalWords : 0.0;
        result.add(DailyWpm(
          date: date,
          avgWpm: avg,
          sessionsCount: daySessions.length,
        ));
      }
    }

    return result;
  }
}

final analyticsServiceProvider = Provider<AnalyticsService>((ref) {
  return AnalyticsService();
});
