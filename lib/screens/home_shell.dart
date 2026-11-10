import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:runthru/design/design.dart';
import 'package:runthru/screens/analytics_screen.dart';
import 'package:runthru/screens/library_screen.dart';
import 'package:runthru/screens/settings_screen.dart';
import 'package:runthru/screens/sources_screen.dart';
import 'package:runthru/services/purchase_service.dart';
import 'package:runthru/widgets/unlock_sheet.dart';

/// Shell that wraps the four main tabs in a [PageView] with a bottom
/// navigation bar. Swipe left/right to move between pages.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({
    super.key,
    this.initialTab = 0,
    this.focusGoogleDriveBrowserSetting = false,
    this.focusRequestId,
  });

  final int initialTab;

  /// Whether Settings should scroll to the full Drive browser setting.
  final bool focusGoogleDriveBrowserSetting;

  /// Unique request token for repeated focus requests.
  final String? focusRequestId;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  late final PageController _pageController;
  int _currentIndex = 0;
  int _displayedNavIndex = 0;
  int? _pendingNavIndex;
  bool _navIsTransitioning = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialTab.clamp(0, 3);
    _displayedNavIndex = _currentIndex;
    _pageController = PageController(initialPage: _currentIndex);
    _pageController.addListener(_syncNavTransitionState);
  }

  @override
  void dispose() {
    _pageController.removeListener(_syncNavTransitionState);
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant HomeShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextIndex = widget.initialTab.clamp(0, 3);
    // The route's tab is a request, not state. The router rebuilds this page
    // whenever a pushed route pops (leaving the reader, for one), and
    // re-applying a stale `?tab=` then sent the reader's Back button to
    // whichever tab a link had opened earlier instead of the Library.
    final isNewRequest =
        nextIndex != oldWidget.initialTab.clamp(0, 3) ||
        widget.focusRequestId != oldWidget.focusRequestId;
    if (isNewRequest && nextIndex != _currentIndex) {
      setState(() {
        _currentIndex = nextIndex;
        _displayedNavIndex = nextIndex;
        _pendingNavIndex = nextIndex;
        _navIsTransitioning = !isReducedMotion(context);
      });
      if (_pageController.hasClients) {
        if (widget.focusGoogleDriveBrowserSetting || isReducedMotion(context)) {
          _pageController.jumpToPage(nextIndex);
          _settleNavAt(nextIndex);
        } else {
          _pageController.animateToPage(
            nextIndex,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        }
      }
    }
  }

  void _syncNavTransitionState() {
    if (!mounted || !_pageController.hasClients) return;
    final page = _pageController.page;
    if (page == null) return;
    if (_pendingNavIndex != null && (page - _pendingNavIndex!).abs() <= 0.01) {
      _settleNavAt(_pendingNavIndex!);
      return;
    }
    final rounded = page.round().clamp(0, 3);
    final displayed = _pendingNavIndex ?? rounded;
    final isBetweenPages =
        _pendingNavIndex != null || (page - rounded).abs() > 0.01;
    if (_displayedNavIndex == displayed &&
        _navIsTransitioning == isBetweenPages) {
      return;
    }
    setState(() {
      _displayedNavIndex = displayed;
      _navIsTransitioning = isBetweenPages;
    });
  }

  void _settleNavAt(int index) {
    if (!mounted) return;
    setState(() {
      _currentIndex = index;
      _displayedNavIndex = index;
      _pendingNavIndex = null;
      _navIsTransitioning = false;
    });
    _syncRouteToTab(index);
  }

  void _onPageChanged(int index) {
    if (!mounted) return;
    setState(() {
      _currentIndex = index;
      _displayedNavIndex = _pendingNavIndex ?? index;
    });
    // A swipe between tabs (no nav tap pending) settles here.
    if (_pendingNavIndex == null) _syncRouteToTab(index);
  }

  /// Keeps the route's `?tab=` equal to the visible tab, so a later link to
  /// a tab (the Library's "Add a source") is always a new request, even
  /// after the reader moved away from the tab an earlier link opened.
  void _syncRouteToTab(int index) {
    final router = GoRouter.maybeOf(context);
    if (router == null) return;
    final uri = router.routeInformationProvider.value.uri;
    if (uri.path != '/') return;
    final current = int.tryParse(uri.queryParameters['tab'] ?? '') ?? 0;
    if (current == index) return;
    router.go(index == 0 ? '/' : '/?tab=$index');
  }

  void _onNavTapped(int index) {
    if (index == _currentIndex) return;
    if (isReducedMotion(context)) {
      _settleNavAt(index);
      _pageController.jumpToPage(index);
    } else {
      setState(() {
        _displayedNavIndex = index;
        _pendingNavIndex = index;
        _navIsTransitioning = true;
      });
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
      extendBody: true,
      body: PageView(
        controller: _pageController,
        onPageChanged: _onPageChanged,
        children: [
          // Screen-level semantic containers so assistive technology
          // announces which tab is active.
          _KeepAlivePage(
            child: Semantics(
              container: true,
              explicitChildNodes: true,
              label: 'Library screen',
              child: const LibraryScreen(),
            ),
          ),
          _KeepAlivePage(
            child: Semantics(
              container: true,
              explicitChildNodes: true,
              label: 'Sources screen',
              child: const SourcesScreen(),
            ),
          ),
          _KeepAlivePage(
            child: Semantics(
              container: true,
              explicitChildNodes: true,
              label: 'Analytics screen',
              child: const _AnalyticsTab(),
            ),
          ),
          _KeepAlivePage(
            child: Semantics(
              container: true,
              explicitChildNodes: true,
              label: 'Settings screen',
              child: SettingsScreen(
                focusGoogleDriveBrowserSetting:
                    widget.focusGoogleDriveBrowserSetting,
                focusRequestId: widget.focusRequestId,
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _DesignerBottomNav(
        currentIndex: _displayedNavIndex,
        isTransitioning: _navIsTransitioning,
        onTap: _onNavTapped,
      ),
    );
  }
}

class _DesignerBottomNav extends StatefulWidget {
  const _DesignerBottomNav({
    required this.currentIndex,
    required this.isTransitioning,
    required this.onTap,
  });

  final int currentIndex;
  final bool isTransitioning;
  final ValueChanged<int> onTap;

  static const _items = [
    (
      icon: Icons.library_books_outlined,
      active: Icons.library_books,
      label: 'Library',
    ),
    (icon: Icons.add_link_outlined, active: Icons.add_link, label: 'Sources'),
    (
      icon: Icons.auto_graph_outlined,
      active: Icons.auto_graph,
      label: 'Analytics',
    ),
    (icon: Icons.settings_outlined, active: Icons.settings, label: 'Settings'),
  ];

  @override
  State<_DesignerBottomNav> createState() => _DesignerBottomNavState();
}

class _DesignerBottomNavState extends State<_DesignerBottomNav> {
  static const double _pillW = 50;
  static const double _circleW = 34;
  static const double _puckH = 34;
  static const Cubic _travel = Cubic(0.5, 0.05, 0.2, 1);

  double _puckCx = 0;
  double _puckW = _pillW;
  double _whispCx = 0;
  Duration _xDur = Duration.zero;
  Duration _wDur = Duration.zero;
  bool _ready = false;
  bool _traveling = false;
  double? _lastItemW;

  final List<Timer> _timers = [];

  @override
  void dispose() {
    _clearTimers();
    super.dispose();
  }

  void _clearTimers() {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
  }

  double _centerOf(int i) => _lastItemW! * i + _lastItemW! / 2;

  void _initPosition(double itemW) {
    if (_ready) return;
    _ready = true;
    _puckCx = itemW * widget.currentIndex + itemW / 2;
    _whispCx = _puckCx;
    _puckW = _pillW;
    _xDur = Duration.zero;
    _wDur = Duration.zero;
  }

  void _travelTo(double cx) {
    if (isReducedMotion(context)) {
      setState(() {
        _puckCx = cx;
        _whispCx = cx;
        _xDur = Duration.zero;
        _wDur = Duration.zero;
      });
      return;
    }
    _clearTimers();
    // Pinch to circle
    setState(() {
      _traveling = true;
      _puckW = _circleW;
      _wDur = const Duration(milliseconds: 150);
      _xDur = Duration.zero;
    });
    // Glide to target
    _timers.add(
      Timer(const Duration(milliseconds: 160), () {
        if (!mounted) return;
        setState(() {
          _puckCx = cx;
          _whispCx = cx;
          _xDur = const Duration(milliseconds: 290);
          _wDur = Duration.zero;
        });
      }),
    );
    // Settle back to pill
    _timers.add(
      Timer(const Duration(milliseconds: 460), () {
        if (!mounted) return;
        setState(() {
          _traveling = false;
          _puckW = _pillW;
          _wDur = const Duration(milliseconds: 190);
          _xDur = Duration.zero;
        });
      }),
    );
  }

  @override
  void didUpdateWidget(_DesignerBottomNav old) {
    super.didUpdateWidget(old);
    if (widget.currentIndex != old.currentIndex && _lastItemW != null) {
      _travelTo(_centerOf(widget.currentIndex));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
          child: Container(
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
            decoration: RunThruDecorations.designerRaised(borderRadius: 24),
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth <= 0) return const SizedBox.shrink();
                final itemW =
                    constraints.maxWidth / _DesignerBottomNav._items.length;
                _lastItemW = itemW;
                if (!_ready) {
                  _initPosition(itemW);
                } else if (!_traveling) {
                  // Re-pin the resting indicator to the live item center when
                  // the layout width changes (e.g. first-launch insets/route
                  // transition settle a frame after the initial pass). Without
                  // this the puck stays frozen at a stale center while the
                  // icons sit at the corrected centers, so the emboss reads as
                  // misaligned until the first tab change recomputes it.
                  final rest = _centerOf(widget.currentIndex);
                  if (_puckCx != rest) {
                    _puckCx = rest;
                    _whispCx = rest;
                    _xDur = Duration.zero;
                    _wDur = Duration.zero;
                  }
                }

                final contentH = constraints.maxHeight;
                final puckTop = (contentH - _puckH) / 2;
                const whispH = 44.0;
                const whispW = 70.0;
                final whispTop = (contentH - whispH) / 2;
                final puckLeft = (_puckCx - _puckW / 2).clamp(
                  0.0,
                  math.max<double>(0.0, constraints.maxWidth - _puckW),
                );
                final whispLeft = (_whispCx - whispW / 2).clamp(
                  0.0,
                  math.max<double>(0.0, constraints.maxWidth - whispW),
                );

                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Teal whisp glow
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 420),
                      curve: _travel,
                      left: whispLeft,
                      top: whispTop,
                      child: IgnorePointer(
                        child: Container(
                          width: whispW,
                          height: whispH,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            gradient: RadialGradient(
                              colors: [
                                RunThruTokens.shellTeal.withAlpha(87),
                                RunThruTokens.shellTeal.withAlpha(26),
                                Colors.transparent,
                              ],
                              stops: const [0.0, 0.55, 1.0],
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Neumorphic puck
                    AnimatedPositioned(
                      duration: _xDur,
                      curve: _travel,
                      left: puckLeft,
                      top: puckTop,
                      child: IgnorePointer(
                        child: AnimatedContainer(
                          duration: _wDur,
                          curve: Curves.ease,
                          width: _puckW,
                          height: _puckH,
                          decoration: RunThruDecorations.raisedDecoration(
                            RunThruSurface.shell,
                            size: RunThruShadowSize.small,
                            borderRadius: 999,
                          ),
                        ),
                      ),
                    ),
                    // Items row (above puck in stack order)
                    Positioned.fill(
                      child: Row(
                        children: [
                          for (
                            var i = 0;
                            i < _DesignerBottomNav._items.length;
                            i++
                          )
                            Expanded(
                              child: _DesignerNavItem(
                                icon: _DesignerBottomNav._items[i].icon,
                                activeIcon: _DesignerBottomNav._items[i].active,
                                label: _DesignerBottomNav._items[i].label,
                                selected: i == widget.currentIndex,
                                isTransitioning:
                                    widget.isTransitioning &&
                                    i == widget.currentIndex,
                                onTap: () => widget.onTap(i),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _DesignerNavItem extends StatelessWidget {
  const _DesignerNavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.isTransitioning,
    required this.onTap,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final bool isTransitioning;
  final VoidCallback onTap;

  static const double _circleSize = 46.0;

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? RunThruTokens.shellTealDeep
        : RunThruTokens.shellInkSoft;

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox.expand(
          child: Center(
            child: AnimatedContainer(
              key: ValueKey('home-nav-indicator-$label'),
              duration: const Duration(milliseconds: 190),
              curve: Curves.ease,
              width: _circleSize,
              height: _circleSize,
              child: Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: Icon(
                    selected ? activeIcon : icon,
                    key: ValueKey('nav-icon-$label-$selected'),
                    color: color,
                    size: 21,
                  ),
                ),
              ),
            ),
          ),
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

/// Reading Wins is part of RunThru Unlock.
class _AnalyticsTab extends ConsumerWidget {
  const _AnalyticsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(hasPremiumProvider)) return const AnalyticsScreen();
    return const Scaffold(
      backgroundColor: RunThruTokens.shellBase,
      body: Center(
        child: SingleChildScrollView(
          child: UnlockPrompt(
            title: 'Reading Wins',
            body:
                'Track reading time, streaks and gentle progress notes '
                'with RunThru Unlock.',
            icon: Icons.emoji_events_outlined,
          ),
        ),
      ),
    );
  }
}
