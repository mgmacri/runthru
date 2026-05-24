import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runthru/design/design.dart';
import 'package:runthru/screens/analytics_screen.dart';
import 'package:runthru/screens/library_screen.dart';
import 'package:runthru/screens/settings_screen.dart';
import 'package:runthru/screens/sources_screen.dart';
import 'package:runthru/services/purchase_service.dart';
import 'package:runthru/store/config.dart';
import 'package:runthru/store/models.dart';

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
      backgroundColor: RunThruTokens.shellBase,
      body: PageView(
        controller: _pageController,
        onPageChanged: _onPageChanged,
        children: const [
          _KeepAlivePage(child: LibraryScreen()),
          _KeepAlivePage(child: SourcesScreen()),
          _KeepAlivePage(child: _AnalyticsTab()),
          _KeepAlivePage(child: SettingsScreen()),
        ],
      ),
      bottomNavigationBar: Theme(
        data: Theme.of(context).copyWith(
          navigationBarTheme: NavigationBarThemeData(
            backgroundColor: RunThruTokens.shellBase,
            surfaceTintColor: Colors.transparent,
            indicatorColor: RunThruTokens.shellAccent.withValues(alpha: 0.15),
            iconTheme: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return const IconThemeData(color: RunThruTokens.shellAccent);
              }
              return const IconThemeData(
                color: RunThruTokens.shellTextSecondary,
              );
            }),
            labelTextStyle: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return RunThruTypography.caption.copyWith(
                  color: RunThruTokens.shellAccent,
                );
              }
              return RunThruTypography.caption.copyWith(
                color: RunThruTokens.shellTextSecondary,
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
              icon: Icon(Icons.add_link_outlined),
              selectedIcon: Icon(Icons.add_link),
              label: 'Sources',
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
      backgroundColor: RunThruTokens.shellBase,
      appBar: AppBar(
        backgroundColor: RunThruTokens.shellBase,
        elevation: 0,
        title: const Text('Premium Feature', style: RunThruTypography.title),
        automaticallyImplyLeading: false,
        iconTheme: const IconThemeData(color: RunThruTokens.shellTextPrimary),
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
                color: RunThruTokens.shellTextSecondary,
              ),
              const SizedBox(height: 16),
              const Text(
                'Reading Analytics is a premium feature',
                style: RunThruTypography.title,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Upgrade to track reading time, streaks, and gentle progress notes.',
                style: RunThruTypography.body,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: RunThruTokens.shellAccent,
                  foregroundColor: RunThruTokens.shellBase,
                ),
                icon: const Icon(Icons.lock_open, size: 18),
                label: Text(
                  'Unlock Premium',
                  style: RunThruTypography.body.copyWith(
                    color: RunThruTokens.shellBase,
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
