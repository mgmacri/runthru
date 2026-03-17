import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speedy_boy/design/design.dart';
import 'package:speedy_boy/services/analytics_service.dart';
import 'package:speedy_boy/store/analytics_models.dart';
import 'package:speedy_boy/widgets/neumorphic_card.dart';

/// Screen displaying reading analytics: WPM chart, stats cards, streak.
class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen> {
  ReadingStats? _stats;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final service = ref.read(analyticsServiceProvider);
    final stats = await service.calculateStats();
    if (mounted) {
      setState(() {
        _stats = stats;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpeedyBoyTokens.shellBase,
      appBar: AppBar(
        backgroundColor: SpeedyBoyTokens.shellBase,
        elevation: 0,
        title: const Text(
          'Reading Analytics',
          style: SpeedyBoyTypography.title,
        ),
        iconTheme: const IconThemeData(
          color: SpeedyBoyTokens.shellTextPrimary,
        ),
      ),
      body: _loading
          ? Center(
              child: Text(
                'Loading...',
                style: SpeedyBoyTypography.body.copyWith(
                  color: SpeedyBoyTokens.shellTextSecondary,
                ),
              ),
            )
          : _buildContent(),
    );
  }

  Widget _buildContent() {
    final stats = _stats ?? const ReadingStats();

    if (stats.totalSessions == 0) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.auto_graph,
                size: 48,
                color: SpeedyBoyTokens.shellTextSecondary.withAlpha(120),
              ),
              const SizedBox(height: 16),
              const Text(
                'No reading sessions yet',
                style: SpeedyBoyTypography.title,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Start reading a PDF to see your analytics here.',
                style: SpeedyBoyTypography.body.copyWith(
                  color: SpeedyBoyTokens.shellTextSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        // ── WPM Over Time Chart ──
        if (stats.wpmHistory.isNotEmpty)
          NeumorphicCard(
            surface: SpeedyBoySurface.shell,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'WPM Over Time',
                  style: SpeedyBoyTypography.title,
                ),
                const SizedBox(height: 4),
                Text(
                  'Last 30 days',
                  style: SpeedyBoyTypography.caption.copyWith(
                    color: SpeedyBoyTokens.shellTextSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 200,
                  child: _WpmChart(history: stats.wpmHistory),
                ),
              ],
            ),
          ),

        // ── Stat Cards Row ──
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              Expanded(
                child: _StatCard(
                  label: 'Words',
                  value: _formatNumber(stats.totalWordsRead),
                ),
              ),
              Expanded(
                child: _StatCard(
                  label: 'Sessions',
                  value: stats.totalSessions.toString(),
                ),
              ),
              Expanded(
                child: _StatCard(
                  label: 'Streak',
                  value: stats.streak.toString(),
                  icon: Icons.local_fire_department,
                  iconColor: SpeedyBoyTokens.shellError,
                ),
              ),
            ],
          ),
        ),

        // ── Average WPM Card ──
        NeumorphicCard(
          surface: SpeedyBoySurface.shell,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Average WPM',
                      style: SpeedyBoyTypography.title,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Weighted by words read per session',
                      style: SpeedyBoyTypography.caption.copyWith(
                        color: SpeedyBoyTokens.shellTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                stats.avgWpm.round().toString(),
                style: SpeedyBoyTypography.display.copyWith(
                  color: SpeedyBoyTokens.shellAccent,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatNumber(int n) {
    if (n >= 1000000) {
      return '${(n / 1000000).toStringAsFixed(1)}M';
    } else if (n >= 1000) {
      return '${(n / 1000).toStringAsFixed(1)}K';
    }
    return n.toString();
  }
}

/// Neumorphic stat card for the summary row.
class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    this.icon,
    this.iconColor,
  });

  final String label;
  final String value;
  final IconData? icon;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return NeumorphicCard(
      surface: SpeedyBoySurface.shell,
      size: SpeedyBoyShadowSize.small,
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: iconColor),
                const SizedBox(width: 4),
              ],
              Flexible(
                child: Text(
                  value,
                  style: SpeedyBoyTypography.badge,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: SpeedyBoyTypography.caption,
          ),
        ],
      ),
    );
  }
}

/// Line chart showing daily average WPM over the last 30 days.
class _WpmChart extends StatelessWidget {
  const _WpmChart({required this.history});

  final List<DailyWpm> history;

  @override
  Widget build(BuildContext context) {
    if (history.isEmpty) return const SizedBox.shrink();

    // Build spots from history.
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final cutoff = todayDate.subtract(const Duration(days: 29));

    final spots = <FlSpot>[];
    for (final entry in history) {
      final dayIndex = entry.date.difference(cutoff).inDays.toDouble();
      if (dayIndex >= 0 && dayIndex <= 29) {
        spots.add(FlSpot(dayIndex, entry.avgWpm));
      }
    }

    if (spots.isEmpty) return const SizedBox.shrink();

    // Sort by x.
    spots.sort((a, b) => a.x.compareTo(b.x));

    final maxWpm = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    final minWpm = spots.map((s) => s.y).reduce((a, b) => a < b ? a : b);
    final yMax = (maxWpm + 50).ceilToDouble();
    final yMin = (minWpm - 50).clamp(0, double.infinity).floorToDouble();

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: 29,
        minY: yMin,
        maxY: yMax,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: ((yMax - yMin) / 4).clamp(1, double.infinity),
          getDrawingHorizontalLine: (_) => const FlLine(
            color: SpeedyBoyTokens.shellDarkShadow,
            strokeWidth: 0.5,
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: 7,
              getTitlesWidget: (value, meta) {
                final date = cutoff.add(Duration(days: value.toInt()));
                return SideTitleWidget(
                  axisSide: meta.axisSide,
                  child: Text(
                    '${date.month}/${date.day}',
                    style: SpeedyBoyTypography.caption.copyWith(fontSize: 10),
                  ),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              getTitlesWidget: (value, meta) {
                return SideTitleWidget(
                  axisSide: meta.axisSide,
                  child: Text(
                    value.toInt().toString(),
                    style: SpeedyBoyTypography.caption.copyWith(fontSize: 10),
                  ),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.3,
            color: SpeedyBoyTokens.shellAccent,
            barWidth: 2.5,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, _, __, ___) => FlDotCirclePainter(
                radius: 3,
                color: SpeedyBoyTokens.shellAccent,
                strokeWidth: 1.5,
                strokeColor: SpeedyBoyTokens.shellBase,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              color: SpeedyBoyTokens.shellAccent.withAlpha(30),
            ),
          ),
        ],
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => SpeedyBoyTokens.shellTextPrimary,
            getTooltipItems: (spots) => spots.map((spot) {
              return LineTooltipItem(
                '${spot.y.round()} WPM',
                SpeedyBoyTypography.caption.copyWith(
                  color: SpeedyBoyTokens.shellBase,
                  fontWeight: FontWeight.w600,
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}
