import 'package:flutter/material.dart';

/// Single source of truth for all Speedy Boy colors.
/// This is the ONLY file that may contain raw Color(0xFF...) constructors.
///
/// Palette sourced from the Speedy Boy Design-Colors spec.
class SpeedyBoyTokens extends ThemeExtension<SpeedyBoyTokens> {
  const SpeedyBoyTokens._();

  // ── Reading Stage (dark cube interior) ──
  // stageBase = Black Bean
  static const Color stageBase = Color(0xFF2E272A);
  // stageLightShadow = Fudge
  static const Color stageLightShadow = Color(0xFF493338);
  // stageDarkShadow = derived deep brown
  static const Color stageDarkShadow = Color(0xFF1A1517);
  // stageText = Bright White
  static const Color stageText = Color(0xFFF4F5F0);
  // stageAnchor default = Hot Coral (user can override)
  static const Color stageAnchor = Color(0xFFED5656);
  // stageProgress = Sea Green
  static const Color stageProgress = Color(0xFF149C88);
  // stagePauseOverlay = Dress Blues
  static const Color stagePauseOverlay = Color(0xFF2A3244);
  // stageWpmBadge = Wild Dove
  static const Color stageWpmBadge = Color(0xFF8B8E8D);

  // ── UI Shell (warm off-white neumorphic) ──
  // shellBase = Antique White
  static const Color shellBase = Color(0xFFEDE3D2);
  // shellLightShadow = Bright White
  static const Color shellLightShadow = Color(0xFFF4F5F0);
  // shellDarkShadow = Birch
  static const Color shellDarkShadow = Color(0xFFDDD5C7);
  // shellTextPrimary = Black Bean
  static const Color shellTextPrimary = Color(0xFF2E272A);
  // shellTextSecondary = Dark Gull Gray
  static const Color shellTextSecondary = Color(0xFF625D5D);
  // shellAccent = Brittany Blue
  static const Color shellAccent = Color(0xFF4C7E86);
  // shellProcessing = Marigold Color
  static const Color shellProcessing = Color(0xFFFDAC53);
  // shellReady = Sea Green
  static const Color shellReady = Color(0xFF149C88);
  // shellError = Hot Coral
  static const Color shellError = Color(0xFFED5656);

  // ── WPM Dial ring gradient ──
  // Low = Brittany Blue, Mid = Marigold, High = Hot Coral
  static const Color dialRingLow = Color(0xFF4C7E86);
  static const Color dialRingMid = Color(0xFFFDAC53);
  static const Color dialRingHigh = Color(0xFFED5656);

  // ── 3D Cube wall faces ──
  // Back wall: darkest (derived)
  static const Color cubeBackWall = Color(0xFF1A1517);
  // Left wall: Dress Blues
  static const Color cubeLeftWall = Color(0xFF2A3244);
  // Right wall: Fudge
  static const Color cubeRightWall = Color(0xFF493338);
  // Top wall: Dark Slate
  static const Color cubeTopWall = Color(0xFF46515A);
  // Bottom wall: Majolica Blue
  static const Color cubeBottomWall = Color(0xFF274357);
  // Edge highlight: Marsala
  static const Color cubeEdgeGlow = Color(0xFF964F4C);
  // Ambient = same as back wall
  static const Color cubeAmbient = Color(0xFF1A1517);
  // Directional light hint = Bright White
  static const Color cubeDirectional = Color(0xFFF4F5F0);
  // Rim shadow
  static const Color cubeRimShadow = Color(0x80000000);

  // ── Stereoscopic ──
  // stereoIndicator = Sea Green
  static const Color stereoIndicator = Color(0xFF149C88);

  // ── Anchor color palette (Bright group from design palette) ──
  static const List<Color> anchorColors = [
    Color(0xFFED5656), // Hot Coral
    Color(0xFFFFA44A), // Blazing Orange
    Color(0xFFFDAC53), // Marigold Color
    Color(0xFFFBE337), // Buttercup
    Color(0xFFF0E87D), // Limelight
    Color(0xFFB5CF71), // Green Glow
    Color(0xFF149C88), // Sea Green
    Color(0xFF0078BE), // Brilliant Blue
    Color(0xFF195190), // Turkish Sea Color
    Color(0xFFD33479), // Fuscia Purple
    Color(0xFFAD5E99), // Radiant Orchid
    Color(0xFFC71F2D), // High Risk Red
  ];

  static const List<String> anchorColorNames = [
    'Hot Coral',
    'Blazing Orange',
    'Marigold',
    'Buttercup',
    'Limelight',
    'Green Glow',
    'Sea Green',
    'Brilliant Blue',
    'Turkish Sea',
    'Fuscia Purple',
    'Radiant Orchid',
    'High Risk Red',
  ];

  static const SpeedyBoyTokens instance = SpeedyBoyTokens._();

  @override
  SpeedyBoyTokens copyWith() => this;

  @override
  SpeedyBoyTokens lerp(
    covariant ThemeExtension<SpeedyBoyTokens>? other,
    double t,
  ) =>
      this;
}
