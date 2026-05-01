import 'package:runthru/three_d/glyph_measurer.dart';
import 'package:runthru/three_d/off_axis_projection.dart';

/// Computes font size so the longest reasonable word (~12 chars) fills
/// approximately 80% of the back wall's visible width at the current
/// head position.
///
/// ## How it works
///
/// 1. Project the back wall's left and right edges to screen space using
///    the current head position and room config.
/// 2. Compute `targetTextScreenWidth = backWallScreenWidth * 0.80`.
/// 3. Measure a 12-char reference word ("COMPENSATION") at a trial font size.
/// 4. Scale: `fontSize = trial * (targetWidth / measuredWidth)`.
/// 5. Clamp to [16, 600] for safety.
///
/// The result is cached and only recomputed when the head position changes
/// by more than [_headThreshold] units or the viewport size changes.
///
/// ## textZ vs roomDepth
///
/// The text sits at `config.textZ` which is intentionally *in front of* the
/// back wall at `config.roomDepth`. The text is **sized** as if it were on
/// the back wall, but **positioned** slightly forward so it appears to float
/// just above the marble surface — matching the neumorphic raised aesthetic.
class BackWallFontSizer {
  BackWallFontSizer();

  static const String _referenceWord = 'COMPENSATION';
  static const double _trialSize = 100.0;
  static const double _fillFraction = 0.80;
  static const double _minFontSize = 16.0;
  static const double _maxFontSize = 600.0;
  static const double _headThreshold = 0.5;

  // Cached state
  double _cachedFontSize = 48.0;
  double _lastHeadX = double.nan;
  double _lastHeadY = double.nan;
  double _lastScreenW = 0;
  double _lastScreenH = 0;

  /// Previous font size for smooth lerping between words.
  double previousFontSize = 48.0;

  /// Current target font size (before word-length adaptation).
  double currentFontSize = 48.0;

  /// Compute the base font size from the back wall geometry.
  ///
  /// If head position / viewport hasn't changed significantly,
  /// returns the cached value without re-measuring.
  double computeBaseFontSize(
    RoomConfig config,
    double headX,
    double headY,
    double screenWidth,
    double screenHeight,
  ) {
    // Check if recomputation is needed
    final headMoved = (headX - _lastHeadX).abs() > _headThreshold ||
        (headY - _lastHeadY).abs() > _headThreshold ||
        _lastHeadX.isNaN;
    final sizeChanged =
        screenWidth != _lastScreenW || screenHeight != _lastScreenH;

    if (!headMoved && !sizeChanged) return _cachedFontSize;

    _lastHeadX = headX;
    _lastHeadY = headY;
    _lastScreenW = screenWidth;
    _lastScreenH = screenHeight;

    // Project back wall edges to screen space
    final leftScreen = projectOffAxis(
      Point3D(-config.wRoom, 0, config.roomDepth),
      headX: headX,
      headY: headY,
      config: config,
      screenWidth: screenWidth,
      screenHeight: screenHeight,
    );
    final rightScreen = projectOffAxis(
      Point3D(config.wRoom, 0, config.roomDepth),
      headX: headX,
      headY: headY,
      config: config,
      screenWidth: screenWidth,
      screenHeight: screenHeight,
    );

    if (leftScreen == null || rightScreen == null) return _cachedFontSize;

    final backWallScreenWidth = (rightScreen.dx - leftScreen.dx).abs();
    final targetWidth = backWallScreenWidth * _fillFraction;

    // Measure reference word at trial size
    final refWidth = GlyphMeasurer.instance.wordWidth(
      _referenceWord,
      _trialSize,
    );
    if (refWidth <= 0) return _cachedFontSize;

    final fontSize =
        (_trialSize * targetWidth / refWidth).clamp(_minFontSize, _maxFontSize);

    _cachedFontSize = fontSize;
    return fontSize;
  }

  /// Compute the final font size adapted for the current word's length.
  ///
  /// - If the word exceeds the target width, shrinks proportionally.
  /// - If the word is very short (< 30% target), does NOT scale up.
  double computeFontSize(
    RoomConfig config,
    double headX,
    double headY,
    double screenWidth,
    double screenHeight,
    String currentWord,
  ) {
    final baseFontSize = computeBaseFontSize(
      config,
      headX,
      headY,
      screenWidth,
      screenHeight,
    );

    if (currentWord.isEmpty) return baseFontSize;

    // Measure back wall target width
    final leftScreen = projectOffAxis(
      Point3D(-config.wRoom, 0, config.roomDepth),
      headX: headX,
      headY: headY,
      config: config,
      screenWidth: screenWidth,
      screenHeight: screenHeight,
    );
    final rightScreen = projectOffAxis(
      Point3D(config.wRoom, 0, config.roomDepth),
      headX: headX,
      headY: headY,
      config: config,
      screenWidth: screenWidth,
      screenHeight: screenHeight,
    );

    if (leftScreen == null || rightScreen == null) return baseFontSize;

    final targetWidth =
        (rightScreen.dx - leftScreen.dx).abs() * _fillFraction;

    // Measure current word at base font size
    final wordWidth = GlyphMeasurer.instance.wordWidth(
      currentWord,
      baseFontSize,
    );

    if (wordWidth > targetWidth) {
      // Scale down to fit
      return baseFontSize * (targetWidth / wordWidth);
    }

    // Don't scale up short words — keep consistent letter height
    return baseFontSize;
  }

  /// Update tracking for smooth transitions between words.
  void onWordChange(double newFontSize) {
    previousFontSize = currentFontSize;
    currentFontSize = newFontSize;
  }

  /// Interpolated font size for smooth transition during word advance.
  double lerpedFontSize(double animationValue) {
    return previousFontSize +
        (currentFontSize - previousFontSize) * animationValue;
  }
}
