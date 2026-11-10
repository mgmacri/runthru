import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:runthru/design/design.dart';
import 'package:runthru/widgets/neumorphic_card.dart';

/// An inset well that pages through its tiles a few at a time.
///
/// The well is as tall as its tallest page so far, whatever the titles wrap
/// to and whatever the system text size is. (A fixed height cut the last
/// row off as soon as a title wrapped or the text size went up.) It does
/// not shrink again under a shorter page, so the indicator stays where the
/// reader tapped it. Swipe sideways, or use the indicator, to change page.
class PagedTileWell extends StatefulWidget {
  /// Creates a paged well of [itemCount] tiles.
  const PagedTileWell({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    required this.label,
    this.tilesPerPage = 4,
  }) : assert(tilesPerPage > 0);

  /// Number of tiles in all.
  final int itemCount;

  /// Builds tile [index].
  final IndexedWidgetBuilder itemBuilder;

  /// What the tiles are ("Books"), for the page indicator's announcement.
  final String label;

  /// Tiles shown on one page.
  final int tilesPerPage;

  /// Space between two tiles on a page.
  static const double tileGap = 9;

  /// Key of the page indicator.
  static const ValueKey<String> indicatorKey = ValueKey<String>(
    'paged-well-indicator',
  );

  @override
  State<PagedTileWell> createState() => PagedTileWellState();
}

/// State of a [PagedTileWell]; exposes the page for tests.
class PagedTileWellState extends State<PagedTileWell>
    with SingleTickerProviderStateMixin {
  /// How far the current page is displaced, in page widths: towards -1 as
  /// the next page comes in from the right, towards 1 as the previous one
  /// comes in from the left.
  late final AnimationController _slide;

  int _page = 0;

  /// The page sliding in beside the current one, if any.
  int? _incoming;

  double _width = 1;

  final GlobalKey _pagesKey = GlobalKey();

  /// Height of the tallest page shown so far, and what it was measured for
  /// (width, text size, tile count): it is forgotten when those change.
  double _tallest = 0;
  Object? _measuredFor;

  /// A drag past this fraction of the width turns the page on release.
  static const double _turnAt = 0.3;

  /// A fling faster than this (page widths per second) turns the page.
  static const double _flingSpeed = 0.9;

  /// How far the first and last page can be pulled the wrong way.
  static const double _edgePull = 0.08;

  /// The page currently shown (0-based).
  int get page => _page;

  /// Number of pages.
  int get pageCount => (widget.itemCount / widget.tilesPerPage).ceil();

  @override
  void initState() {
    super.initState();
    _slide = AnimationController.unbounded(vsync: this);
  }

  @override
  void didUpdateWidget(covariant PagedTileWell oldWidget) {
    super.didUpdateWidget(oldWidget);
    final last = math.max(0, pageCount - 1);
    final incoming = _incoming;
    if (_page > last || (incoming != null && incoming > last)) {
      _slide.stop();
      _slide.value = 0;
      _incoming = null;
      _page = math.min(_page, last);
    }
  }

  @override
  void dispose() {
    _slide.dispose();
    super.dispose();
  }

  bool _exists(int page) => page >= 0 && page < pageCount;

  /// Keeps the well at least as tall as the page just laid out.
  void _rememberHeight() {
    if (!mounted) return;
    final box = _pagesKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    if (box.size.height > _tallest + 0.5) {
      setState(() => _tallest = box.size.height);
    }
  }

  /// Shows [target], sliding to it unless motion is reduced.
  void showPage(int target) {
    if (!_exists(target) || target == _page) return;
    _slide.stop();
    if (isReducedMotion(context)) {
      setState(() {
        _page = target;
        _incoming = null;
        _slide.value = 0;
      });
      return;
    }
    setState(() {
      _incoming = target;
      _slide.value = 0;
    });
    _turnTo(target > _page ? -1 : 1);
  }

  /// Runs the slide out to [end] and makes the incoming page the current one.
  void _turnTo(double end) {
    final incoming = _incoming;
    if (incoming == null) return;
    _slide
        .animateTo(
          end,
          duration: RunThruTiming.shelfPageTurn,
          curve: Curves.easeOutCubic,
        )
        .then<void>((_) {
          if (!mounted || _incoming != incoming) return;
          setState(() {
            _page = incoming;
            _incoming = null;
            _slide.value = 0;
          });
        });
  }

  /// Lets the current page fall back into place.
  void _settleBack() {
    _slide
        .animateTo(
          0,
          duration: RunThruTiming.shelfPageSettle,
          curve: Curves.easeOutCubic,
        )
        .then<void>((_) {
          if (mounted && _incoming != null) setState(() => _incoming = null);
        });
  }

  void _onDragStart(DragStartDetails details) => _slide.stop();

  void _onDragUpdate(DragUpdateDetails details) {
    if (_width <= 0) return;
    final moved = (details.primaryDelta ?? 0) / _width;
    var value = _slide.value + moved;
    final neighbour = value < 0
        ? _page + 1
        : value > 0
        ? _page - 1
        : null;
    final incoming = neighbour != null && _exists(neighbour) ? neighbour : null;
    value = incoming == null
        // Nothing that way: a short, resisted pull.
        ? (_slide.value + moved * 0.35).clamp(-_edgePull, _edgePull)
        : value.clamp(-1.0, 1.0);
    if (incoming != _incoming) setState(() => _incoming = incoming);
    _slide.value = value;
  }

  void _onDragEnd(DragEndDetails details) =>
      _release((details.primaryVelocity ?? 0) / math.max(_width, 1));

  /// Finishes a drag let go at [velocity] page widths per second.
  void _release(double velocity) {
    final value = _slide.value;
    final incoming = _incoming;
    final flung = velocity.abs() > _flingSpeed && velocity.sign == value.sign;
    final turn = incoming != null && (value.abs() > _turnAt || flung);
    if (isReducedMotion(context)) {
      setState(() {
        if (turn) _page = incoming;
        _incoming = null;
        _slide.value = 0;
      });
      return;
    }
    if (turn) {
      _turnTo(value < 0 ? -1 : 1);
    } else {
      _settleBack();
    }
  }

  Widget _buildPage(BuildContext context, int page) {
    final first = page * widget.tilesPerPage;
    final count = (widget.itemCount - first).clamp(0, widget.tilesPerPage);
    return Padding(
      // Vertical room inside the clip, so tile shadows are not cut.
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < count; i++) ...[
            widget.itemBuilder(context, first + i),
            if (i < count - 1) const SizedBox(height: PagedTileWell.tileGap),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reduced = isReducedMotion(context);
    final pages = pageCount;
    final incoming = _incoming;

    Widget well = NeumorphicCard(
      surface: RunThruSurface.shell,
      inset: true,
      size: RunThruShadowSize.small,
      borderRadius: 12,
      margin: EdgeInsets.zero,
      padding: EdgeInsets.zero,
      child: LayoutBuilder(
        builder: (context, constraints) {
          _width = constraints.maxWidth;
          final measuredFor = (
            _width,
            MediaQuery.textScalerOf(context),
            widget.itemCount,
            widget.tilesPerPage,
          );
          if (measuredFor != _measuredFor) {
            _measuredFor = measuredFor;
            _tallest = 0;
          }
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _rememberHeight(),
          );
          final pagesView = ConstrainedBox(
            constraints: BoxConstraints(minHeight: _tallest),
            child: Stack(
              key: _pagesKey,
              // Pages take the well's width and their own height; the well
              // is as tall as the tallest page in view.
              fit: StackFit.passthrough,
              children: [
                _SlidingPage(
                  key: ValueKey<int>(_page),
                  slide: _slide,
                  side: 0,
                  child: _buildPage(context, _page),
                ),
                if (incoming != null)
                  _SlidingPage(
                    key: ValueKey<int>(incoming),
                    slide: _slide,
                    side: incoming > _page ? 1 : -1,
                    child: _buildPage(context, incoming),
                  ),
              ],
            ),
          );
          return ClipRRect(
            borderRadius: BorderRadius.circular(12),
            // The well grows smoothly into a taller page. (No AnimatedSize
            // at all with reduced motion: at zero duration it relayouts
            // itself during layout.)
            child: reduced
                ? pagesView
                : AnimatedSize(
                    duration: RunThruTiming.shelfPageSettle,
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topCenter,
                    child: pagesView,
                  ),
          );
        },
      ),
    );

    if (pages > 1) {
      well = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: _onDragStart,
        onHorizontalDragUpdate: _onDragUpdate,
        onHorizontalDragEnd: _onDragEnd,
        onHorizontalDragCancel: () => _release(0),
        child: well,
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        well,
        if (pages > 1)
          _PageIndicator(
            key: PagedTileWell.indicatorKey,
            label: widget.label,
            page: _page,
            pageCount: pages,
            onPrevious: () => showPage(_page - 1),
            onNext: () => showPage(_page + 1),
          ),
      ],
    );
  }
}

/// One page of the well, displaced sideways by the slide.
class _SlidingPage extends StatelessWidget {
  const _SlidingPage({
    super.key,
    required this.slide,
    required this.side,
    required this.child,
  });

  final Animation<double> slide;

  /// Where the page rests: 0 for the current page, 1 for one coming in
  /// from the right, -1 for one coming in from the left.
  final int side;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: slide,
      child: child,
      builder: (context, child) => FractionalTranslation(
        translation: Offset(slide.value + side, 0),
        child: child,
      ),
    );
  }
}

/// The dots under a paged well.
///
/// One control, a full tap target tall: a tap to the right of the current
/// dot shows the next page, to the left the previous one. At most
/// [_maxDots] dots are drawn; with more pages the row is a window around
/// the current page, its end dots smaller where pages continue.
class _PageIndicator extends StatelessWidget {
  const _PageIndicator({
    super.key,
    required this.label,
    required this.page,
    required this.pageCount,
    required this.onPrevious,
    required this.onNext,
  });

  final String label;
  final int page;
  final int pageCount;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  static const int _maxDots = 7;
  static const double _dot = 7;
  static const double _selectedDot = 17;
  static const double _gap = 6;

  @override
  Widget build(BuildContext context) {
    final shown = math.min(pageCount, _maxDots);
    final first = pageCount <= _maxDots
        ? 0
        : (page - _maxDots ~/ 2).clamp(0, pageCount - _maxDots);
    final last = first + shown - 1;
    final hasPrevious = page > 0;
    final hasNext = page < pageCount - 1;
    final duration = isReducedMotion(context)
        ? Duration.zero
        : RunThruTiming.shelfPageSettle;

    return Semantics(
      container: true,
      label: '$label pages',
      value: 'Page ${page + 1} of $pageCount',
      increasedValue: hasNext ? 'Page ${page + 2} of $pageCount' : null,
      decreasedValue: hasPrevious ? 'Page $page of $pageCount' : null,
      onIncrease: hasNext ? onNext : null,
      onDecrease: hasPrevious ? onPrevious : null,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final rowWidth = (shown - 1) * (_dot + _gap) + _selectedDot;
          final selectedCentre =
              (constraints.maxWidth - rowWidth) / 2 +
              (page - first) * (_dot + _gap) +
              _selectedDot / 2;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) {
              final dx = details.localPosition.dx - selectedCentre;
              if (dx > _selectedDot / 2 && hasNext) {
                onNext();
              } else if (dx < -_selectedDot / 2 && hasPrevious) {
                onPrevious();
              }
            },
            child: SizedBox(
              height: RunThruA11y.minTapTarget,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var index = first; index <= last; index++) ...[
                    AnimatedContainer(
                      duration: duration,
                      curve: Curves.easeOutCubic,
                      width: index == page
                          ? _selectedDot
                          : _dotSize(index, first, last),
                      height: _dotSize(index, first, last),
                      decoration: BoxDecoration(
                        color: index == page
                            ? RunThruTokens.shellTeal
                            : RunThruTokens.shellInkSoft.withValues(
                                alpha: 0.34,
                              ),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    if (index < last) const SizedBox(width: _gap),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// An end dot is smaller when pages go on beyond it.
  double _dotSize(int index, int first, int last) {
    final continues =
        (index == first && first > 0) ||
        (index == last && last < pageCount - 1);
    return continues && index != page ? _dot * 0.6 : _dot;
  }
}
