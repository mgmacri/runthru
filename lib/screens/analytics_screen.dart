import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runthru/design/design.dart';
import 'package:runthru/services/analytics_service.dart';
import 'package:runthru/store/analytics_models.dart';
import 'package:runthru/widgets/neumorphic_card.dart';

final _readingStatsProvider = FutureProvider<ReadingStats>((ref) {
  return ref.watch(analyticsServiceProvider).calculateStats();
});

/// Screen displaying reading momentum, time spent, streaks, and encouragement.
class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(_readingStatsProvider);

    return Scaffold(
      backgroundColor: RunThruTokens.shellBase,
      appBar: AppBar(
        backgroundColor: RunThruTokens.shellBase,
        elevation: 0,
        title: const Text('Reading Wins', style: RunThruTypography.title),
        iconTheme: const IconThemeData(color: RunThruTokens.shellTextPrimary),
      ),
      body: stats.when(
        data: _buildContent,
        error: (_, __) => const _MessageState(
          icon: Icons.insights_outlined,
          title: 'Reading wins need a minute',
          message: 'Come back in a moment and your progress should be here.',
        ),
        loading: () => Center(
          child: Text(
            'Loading...',
            style: RunThruTypography.body.copyWith(
              color: RunThruTokens.shellTextSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(ReadingStats stats) {
    if (stats.totalSessions == 0) {
      return const _MessageState(
        icon: Icons.auto_awesome_outlined,
        title: 'Nothing to measure yet',
        message: 'Read something you want to get through, then come back here.',
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        _EncouragementCard(stats: stats),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              Expanded(
                child: _StatCard(
                  label: 'Reading time',
                  value: _formatReadingTime(stats.totalReadingTime),
                  icon: Icons.schedule,
                  iconColor: RunThruTokens.shellAccent,
                ),
              ),
              Expanded(
                child: _StatCard(
                  label: 'Streak',
                  value: _formatStreak(stats.streak),
                  icon: Icons.local_fire_department,
                  iconColor: RunThruTokens.shellProcessing,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              Expanded(
                child: _StatCard(
                  label: 'Today',
                  value: _formatReadingTime(stats.todayReadingTime),
                  icon: Icons.today_outlined,
                  iconColor: RunThruTokens.shellReady,
                ),
              ),
              Expanded(
                child: _StatCard(
                  label: 'This week',
                  value: _formatReadingTime(stats.weekReadingTime),
                  icon: Icons.calendar_view_week_outlined,
                  iconColor: RunThruTokens.shellAccent,
                ),
              ),
            ],
          ),
        ),
        _RhythmCard(history: stats.readingTimeHistory),
        _FeelGoodCard(stats: stats),
      ],
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 48,
              color: RunThruTokens.shellTextSecondary.withAlpha(120),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: RunThruTypography.title,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: RunThruTypography.body.copyWith(
                color: RunThruTokens.shellTextSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _EncouragementCard extends StatelessWidget {
  const _EncouragementCard({required this.stats});

  final ReadingStats stats;

  @override
  Widget build(BuildContext context) {
    return NeumorphicCard(
      surface: RunThruSurface.shell,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _encouragementTitle(stats),
            style: RunThruTypography.display.copyWith(
              color: RunThruTokens.shellTextPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _encouragementMessage(stats),
            style: RunThruTypography.body.copyWith(
              color: RunThruTokens.shellTextSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.iconColor,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return NeumorphicCard(
      surface: RunThruSurface.shell,
      size: RunThruShadowSize.small,
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: iconColor),
          const SizedBox(height: 12),
          Text(
            value,
            style: RunThruTypography.badge,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Text(label, style: RunThruTypography.caption),
        ],
      ),
    );
  }
}

class _RhythmCard extends StatelessWidget {
  const _RhythmCard({required this.history});

  final List<DailyReadingTime> history;

  @override
  Widget build(BuildContext context) {
    final lastWeek = history.length <= 7
        ? history
        : history.sublist(history.length - 7);

    return NeumorphicCard(
      surface: RunThruSurface.shell,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Reading rhythm', style: RunThruTypography.title),
          const SizedBox(height: 4),
          Text(
            'A gentle look at where reading fit this week.',
            style: RunThruTypography.caption.copyWith(
              color: RunThruTokens.shellTextSecondary,
            ),
          ),
          const SizedBox(height: 16),
          Semantics(
            label: 'Reading rhythm for the last seven days',
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final entry in lastWeek)
                  Expanded(child: _RhythmDay(entry: entry)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RhythmDay extends StatelessWidget {
  const _RhythmDay({required this.entry});

  final DailyReadingTime entry;

  @override
  Widget build(BuildContext context) {
    final height = entry.hasReading ? 48.0 : 18.0;
    final color = entry.hasReading
        ? RunThruTokens.shellReady
        : RunThruTokens.shellTextSecondary.withAlpha(90);

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Container(
          width: 18,
          height: height,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(9),
          ),
        ),
        const SizedBox(height: 8),
        Text(_weekdayLabel(entry.date), style: RunThruTypography.caption),
      ],
    );
  }
}

class _FeelGoodCard extends StatelessWidget {
  const _FeelGoodCard({required this.stats});

  final ReadingStats stats;

  @override
  Widget build(BuildContext context) {
    return NeumorphicCard(
      surface: RunThruSurface.shell,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Worth feeling good about',
            style: RunThruTypography.title,
          ),
          const SizedBox(height: 12),
          _FeelGoodRow(
            icon: Icons.check_circle_outline,
            text: stats.todayReadingTime > Duration.zero
                ? 'You made room for reading today.'
                : 'The next reading moment is still available.',
          ),
          _FeelGoodRow(
            icon: Icons.repeat,
            text: stats.streak > 1
                ? 'You came back more than once.'
                : 'Showing up once still counts.',
          ),
          _FeelGoodRow(
            icon: Icons.favorite_border,
            text: stats.totalReadingTime.inMinutes >= 30
                ? 'Your attention has had real practice here.'
                : 'A small start is a real start.',
          ),
        ],
      ),
    );
  }
}

class _FeelGoodRow extends StatelessWidget {
  const _FeelGoodRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: RunThruTokens.shellAccent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: RunThruTypography.body.copyWith(
                color: RunThruTokens.shellTextPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatReadingTime(Duration duration) {
  if (duration < const Duration(minutes: 1)) return 'A few moments';
  if (duration < const Duration(hours: 1)) {
    return 'About ${duration.inMinutes} min';
  }

  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  if (minutes < 10) return 'About $hours hr';
  return 'About $hours hr ${minutes ~/ 10}0 min';
}

String _formatStreak(int streak) {
  if (streak <= 0) return 'Ready';
  if (streak == 1) return '1 day';
  return '$streak days';
}

String _encouragementTitle(ReadingStats stats) {
  if (stats.todayReadingTime > Duration.zero) return 'You read today';
  if (stats.streak > 1) return 'Your streak is waiting';
  return 'You have started';
}

String _encouragementMessage(ReadingStats stats) {
  if (stats.streak >= 7) {
    return 'That is a steady pattern. Keep it kind, and keep it yours.';
  }
  if (stats.todayReadingTime > Duration.zero) {
    return 'You made room for reading, and that counts.';
  }
  if (stats.weekReadingTime >= const Duration(hours: 1)) {
    return 'This week already has meaningful reading time in it.';
  }
  return 'Any amount of reading is still a step through the thing you opened.';
}

String _weekdayLabel(DateTime date) {
  const labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  return labels[date.weekday - 1];
}
