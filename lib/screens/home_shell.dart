import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speedy_boy/design/design.dart';
import 'package:speedy_boy/screens/analytics_screen.dart';
import 'package:speedy_boy/screens/discover_screen.dart';
import 'package:speedy_boy/screens/library_screen.dart';
import 'package:speedy_boy/screens/settings_screen.dart';
import 'package:speedy_boy/services/purchase_service.dart';
import 'package:speedy_boy/store/config.dart';
import 'package:speedy_boy/store/models.dart';

/// Shell that wraps the four main tabs in a [PageView] with a bottom
/// navigation bar. Swipe left/right to move between pages.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  late final PageController _pageController;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialTab.clamp(0, 3);
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    setState(() => _currentIndex = index);
  }

  void _onNavTapped(int index) {
    if (isReducedMotion(context)) {
      _pageController.jumpToPage(index);
    } else {
      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpeedyBoyTokens.shellBase,
      body: PageView(
        controller: _pageController,
        onPageChanged: _onPageChanged,
        children: const [
          _KeepAlivePage(child: LibraryScreen()),
          _KeepAlivePage(child: DiscoverScreen()),
          _KeepAlivePage(child: _AnalyticsTab()),
          _KeepAlivePage(child: SettingsScreen()),
        ],
      ),
      bottomNavigationBar: Theme(
        data: Theme.of(context).copyWith(
          navigationBarTheme: NavigationBarThemeData(
            backgroundColor: SpeedyBoyTokens.shellBase,
            surfaceTintColor: Colors.transparent,
            indicatorColor: SpeedyBoyTokens.shellAccent.withValues(alpha: 0.15),
            iconTheme: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return const IconThemeData(color: SpeedyBoyTokens.shellAccent);
              }
              return const IconThemeData(
                color: SpeedyBoyTokens.shellTextSecondary,
              );
            }),
            labelTextStyle: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return SpeedyBoyTypography.caption.copyWith(
                  color: SpeedyBoyTokens.shellAccent,
                );
              }
              return SpeedyBoyTypography.caption.copyWith(
                color: SpeedyBoyTokens.shellTextSecondary,
              );
            }),
          ),
        ),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: _onNavTapped,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.library_books_outlined),
              selectedIcon: Icon(Icons.library_books),
              label: 'Library',
            ),
            NavigationDestination(
              icon: Icon(Icons.explore_outlined),
              selectedIcon: Icon(Icons.explore),
              label: 'Discover',
            ),
            NavigationDestination(
              icon: Icon(Icons.auto_graph_outlined),
              selectedIcon: Icon(Icons.auto_graph),
              label: 'Analytics',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}

/// Keeps page state alive when swiped out of view.
class _KeepAlivePage extends StatefulWidget {
  const _KeepAlivePage({required this.child});

  final Widget child;

  @override
  State<_KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<_KeepAlivePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

/// Analytics tab with premium gate. Shows [AnalyticsScreen] for premium
/// users, an upsell prompt for free users.
class _AnalyticsTab extends ConsumerWidget {
  const _AnalyticsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(configProvider).valueOrNull ?? const AppConfig();
    if (config.hasPremium || kDebugMode) return const AnalyticsScreen();

    return Scaffold(
      backgroundColor: SpeedyBoyTokens.shellBase,
      appBar: AppBar(
        backgroundColor: SpeedyBoyTokens.shellBase,
        elevation: 0,
        title: const Text('Premium Feature', style: SpeedyBoyTypography.title),
        automaticallyImplyLeading: false,
        iconTheme: const IconThemeData(color: SpeedyBoyTokens.shellTextPrimary),
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
            ],
          ),
        ),
      ),
    );
  }
}
