import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:speedy_boy/design/design.dart';
import 'package:speedy_boy/navigation/cube_transition.dart';
import 'package:speedy_boy/navigation/wall_fold_transition.dart';
import 'package:speedy_boy/screens/analytics_screen.dart';
import 'package:speedy_boy/screens/discover_screen.dart';
import 'package:speedy_boy/screens/library_screen.dart';
import 'package:speedy_boy/screens/parallax_reading_screen.dart';
import 'package:speedy_boy/screens/range_picker_screen.dart';
import 'package:speedy_boy/screens/reading_screen.dart';
import 'package:speedy_boy/screens/settings_screen.dart';
import 'package:speedy_boy/services/purchase_service.dart';
import 'package:speedy_boy/store/config.dart';
import 'package:speedy_boy/store/models.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      pageBuilder: (context, state) => libraryTransitionPage(
        key: state.pageKey,
        child: const LibraryScreen(),
      ),
    ),
    GoRoute(
      path: '/read',
      pageBuilder: (context, state) {
        final filePath = state.uri.queryParameters['path'] ?? '';
        return wallFoldTransitionPage(
          key: state.pageKey,
          child: _PremiumReadGuard(filePath: filePath),
        );
      },
    ),
    GoRoute(
      path: '/read-legacy',
      pageBuilder: (context, state) {
        final filePath = state.uri.queryParameters['path'] ?? '';
        return cubeTransitionPage(
          key: state.pageKey,
          direction: -1,
          child: ReadingScreen(filePath: filePath),
        );
      },
    ),
    GoRoute(
      path: '/range-picker',
      pageBuilder: (context, state) {
        final filePath = state.uri.queryParameters['path'] ?? '';
        return cubeTransitionPage(
          key: state.pageKey,
          child: _PremiumRangePickerGuard(filePath: filePath),
        );
      },
    ),
    GoRoute(
      path: '/analytics',
      pageBuilder: (context, state) => cubeTransitionPage(
        key: state.pageKey,
        child: const _PremiumAnalyticsGuard(),
      ),
    ),
    GoRoute(
      path: '/discover',
      pageBuilder: (context, state) => cubeTransitionPage(
        key: state.pageKey,
        child: const DiscoverScreen(),
      ),
    ),
    GoRoute(
      path: '/settings',
      pageBuilder: (context, state) => cubeTransitionPage(
        key: state.pageKey,
        child: const SettingsScreen(),
      ),
    ),
  ],
);

/// Routes free users to [ReadingScreen] and premium users to
/// [ParallaxReadingScreen].
class _PremiumReadGuard extends ConsumerWidget {
  const _PremiumReadGuard({required this.filePath});

  final String filePath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasPremium = ref.watch(
      configProvider.select((c) => c.valueOrNull?.hasPremium ?? false),
    );
    if (hasPremium) {
      return ParallaxReadingScreen(filePath: filePath);
    }
    return ReadingScreen(filePath: filePath);
  }
}

/// Gates analytics behind premium. Free users see an upgrade prompt.
class _PremiumAnalyticsGuard extends ConsumerWidget {
  const _PremiumAnalyticsGuard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(configProvider).valueOrNull ?? const AppConfig();
    if (config.hasPremium) {
      return const AnalyticsScreen();
    }
    return Scaffold(
      backgroundColor: SpeedyBoyTokens.shellBase,
      appBar: AppBar(
        backgroundColor: SpeedyBoyTokens.shellBase,
        elevation: 0,
        title: const Text('Premium Feature', style: SpeedyBoyTypography.title),
        iconTheme: const IconThemeData(
          color: SpeedyBoyTokens.shellTextPrimary,
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.lock_outline,
                size: 48,
                color: SpeedyBoyTokens.shellTextSecondary,
              ),
              const SizedBox(height: 16),
              const Text(
                'Reading Analytics is a premium feature',
                style: SpeedyBoyTypography.title,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Upgrade to track your reading speed, streaks, and progress over time.',
                style: SpeedyBoyTypography.body,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: SpeedyBoyTokens.shellAccent,
                  foregroundColor: SpeedyBoyTokens.shellBase,
                ),
                icon: const Icon(Icons.lock_open, size: 18),
                label: Text(
                  'Unlock Premium',
                  style: SpeedyBoyTypography.body.copyWith(
                    color: SpeedyBoyTokens.shellBase,
                  ),
                ),
                onPressed: () =>
                    ref.read(purchaseServiceProvider).purchasePremium(),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => context.go('/'),
                child: Text(
                  'Back to Library',
                  style: SpeedyBoyTypography.body.copyWith(
                    color: SpeedyBoyTokens.shellTextSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Gates range-picker behind premium. Free users see the upsell screen.
class _PremiumRangePickerGuard extends ConsumerWidget {
  const _PremiumRangePickerGuard({required this.filePath});

  final String filePath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(configProvider).valueOrNull ?? const AppConfig();
    if (config.hasPremium) {
      return RangePickerScreen(filePath: filePath);
    }
    return const _RangePickerUpsellScreen();
  }
}

/// Upsell screen shown when free users navigate to the range picker.
class _RangePickerUpsellScreen extends ConsumerWidget {
  const _RangePickerUpsellScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: SpeedyBoyTokens.shellBase,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.auto_stories,
                size: 48,
                color: SpeedyBoyTokens.shellTextSecondary,
              ),
              const SizedBox(height: 16),
              const Text(
                'Reading Ranges',
                style: SpeedyBoyTypography.title,
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  'Select exactly which pages to read — perfect for '
                  'assigned chapters or focused review. Available with Premium.',
                  style: SpeedyBoyTypography.body.copyWith(
                    color: SpeedyBoyTokens.shellTextSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: SpeedyBoyTokens.shellAccent,
                  foregroundColor: SpeedyBoyTokens.shellBase,
                ),
                onPressed: () =>
                    ref.read(purchaseServiceProvider).purchasePremium(),
                child: Text(
                  'Upgrade',
                  style: SpeedyBoyTypography.body.copyWith(
                    color: SpeedyBoyTokens.shellBase,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => context.pop(),
                child: Text(
                  'Back to Library',
                  style: SpeedyBoyTypography.body.copyWith(
                    color: SpeedyBoyTokens.shellTextSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
