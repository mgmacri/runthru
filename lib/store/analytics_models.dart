/// Data models for reading analytics.
library;

/// Single reading session record.
class ReadingSession {
  const ReadingSession({
    required this.startTime,
    this.endTime,
    required this.wordsRead,
    required this.avgWpm,
    required this.filePath,
  });

  factory ReadingSession.fromJson(Map<String, Object?> json) {
    return ReadingSession(
      startTime: DateTime.parse(json['startTime'] as String),
      endTime: json['endTime'] != null
          ? DateTime.parse(json['endTime'] as String)
          : null,
      wordsRead: json['wordsRead'] as int? ?? 0,
      avgWpm: (json['avgWpm'] as num?)?.toDouble() ?? 0.0,
      filePath: json['filePath'] as String? ?? '',
    );
  }

  final DateTime startTime;
  final DateTime? endTime;
  final int wordsRead;
  final double avgWpm;
  final String filePath;

  Duration? get duration => endTime?.difference(startTime);

  Map<String, Object?> toJson() => {
    'startTime': startTime.toIso8601String(),
    'endTime': endTime?.toIso8601String(),
    'wordsRead': wordsRead,
    'avgWpm': avgWpm,
    'filePath': filePath,
  };
}

/// Daily aggregated WPM for charting.
class DailyWpm {
  const DailyWpm({
    required this.date,
    required this.avgWpm,
    required this.sessionsCount,
  });

  factory DailyWpm.fromJson(Map<String, Object?> json) {
    return DailyWpm(
      date: DateTime.parse(json['date'] as String),
      avgWpm: (json['avgWpm'] as num?)?.toDouble() ?? 0.0,
      sessionsCount: json['sessionsCount'] as int? ?? 0,
    );
  }

  final DateTime date;
  final double avgWpm;
  final int sessionsCount;

  Map<String, Object?> toJson() => {
    'date': date.toIso8601String(),
    'avgWpm': avgWpm,
    'sessionsCount': sessionsCount,
  };
}

/// Reading time aggregated for a single local day.
class DailyReadingTime {
  const DailyReadingTime({
    required this.date,
    this.readingTime = Duration.zero,
  });

  final DateTime date;
  final Duration readingTime;

  bool get hasReading => readingTime > Duration.zero;
}

/// Aggregate reading statistics.
class ReadingStats {
  const ReadingStats({
    this.totalSessions = 0,
    this.totalWordsRead = 0,
    this.avgWpm = 0.0,
    this.streak = 0,
    this.wpmHistory = const [],
    this.totalReadingTime = Duration.zero,
    this.todayReadingTime = Duration.zero,
    this.weekReadingTime = Duration.zero,
    this.readingTimeHistory = const [],
  });

  final int totalSessions;
  final int totalWordsRead;
  final double avgWpm;
  final int streak;
  final List<DailyWpm> wpmHistory;
  final Duration totalReadingTime;
  final Duration todayReadingTime;
  final Duration weekReadingTime;
  final List<DailyReadingTime> readingTimeHistory;
}
