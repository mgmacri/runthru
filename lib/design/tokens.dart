import 'package:flutter/material.dart';

/// Single source of truth for all RunThru colors.
/// This is the ONLY file that may contain raw Color(0xFF...) constructors.
///
/// RULE: shell* tokens are for the library/settings UI.
///       stage* tokens are for the reading viewport interior.
///       Never cross-reference. See copilot-instructions.md rule 7.
///
/// Palette sourced from the RunThru Design-Colors spec.
class RunThruTokens extends ThemeExtension<RunThruTokens> {
  const RunThruTokens._();

  // ── Reading Stage (neumorphic raised surface) ──
  // stageBase = Antique White (warm light card surface)
  static const Color stageBase = Color(0xFFEDE3D2);
  // stageLightShadow = Bright White (neumorphic highlight)
  static const Color stageLightShadow = Color(0xFFF4F5F0);
  // stageDarkShadow = Birch (neumorphic shadow)
  static const Color stageDarkShadow = Color(0xFFDDD5C7);
  // stageText = Black Bean (dark on light)
  static const Color stageText = Color(0xFF2E272A);
  // stageAnchor default = High Risk Red (better contrast on light surface)
  static const Color stageAnchor = Color(0xFFC71F2D);
  // stageProgress = Sea Green
  static const Color stageProgress = Color(0xFF149C88);
  // stagePauseOverlay = translucent Nimbus Cloud
  static const Color stagePauseOverlay = Color(0xCCD5D5D8);
  // stageWpmBadge = Dark Gull Gray
  static const Color stageWpmBadge = Color(0xFF625D5D);

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
  // shellOnError = near-white for text on error surfaces
  static const Color shellOnError = Color(0xFFF4F5F0);

  // ── WPM Dial ring gradient ──
  // Low = Brittany Blue, Mid = Marigold, High = Hot Coral
  static const Color dialRingLow = Color(0xFF4C7E86);
  static const Color dialRingMid = Color(0xFFFDAC53);
  static const Color dialRingHigh = Color(0xFFED5656);

  // ── 3D Marble Box (warm polished marble interior) ──
  // Warm whites and soft greys create an elegant Carrara marble feel.
  // Base surface: soft warm white marble
  static const Color cubeBase = Color(0xFFF5F0EA);
  // Back wall: slightly cooler white (subtle depth)
  static const Color cubeBackWall = Color(0xFFEDE8E2);
  // Left wall: warm grey with pink undertone
  static const Color cubeLeftWall = Color(0xFFE8E0D8);
  // Right wall: warm grey (mirrored)
  static const Color cubeRightWall = Color(0xFFE8E0D8);
  // Top wall: lightest (lit from above)
  static const Color cubeTopWall = Color(0xFFF0EBE5);
  // Bottom wall: slightly deeper warm grey
  static const Color cubeBottomWall = Color(0xFFE2DAD0);
  // Edge highlight: soft white glow
  static const Color cubeEdgeGlow = Color(0xFFFAF7F4);
  // Ambient = base
  static const Color cubeAmbient = Color(0xFFF5F0EA);
  // Directional light hint = warm cream
  static const Color cubeDirectional = Color(0xFFF8F4EE);
  // Neumorphic light shadow (highlight) — bright white edge
  static const Color cubeNeuLight = Color(0xFFFFFEFC);
  // Neumorphic dark shadow — soft warm shadow
  static const Color cubeNeuDark = Color(0xFFD5CCC0);
  // Rim shadow — subtle warm inset
  static const Color cubeRimShadow = Color(0x20A09080);

  // ── Marble Box interior ──
  // Vein primary — soft grey-blue marble veining
  static const Color marbleVeinPrimary = Color(0xFFB8B0A8);
  // Vein secondary — faint warm blush veining
  static const Color marbleVeinSecondary = Color(0xFFD0C4B8);
  // Vein highlight — translucent crystalline gleam
  static const Color marbleVeinHighlight = Color(0x30FFFFFF);
  // Marble surface glow — warm light pooling on polished surface
  static const Color marbleSurfaceGlow = Color(0x18F0E0D0);
  // Grid lines — subtle etched lines in marble
  static const Color roomGridLine = Color(0xFFD0C8BE);
  // Grid far — barely visible at depth
  static const Color roomGridFar = Color(0xFFE8E2DC);
  // Room background — warm marble white
  static const Color roomBackground = Color(0xFFF2EDE7);
  // Room fog — warm atmospheric haze
  static const Color roomFog = Color(0xFFF0EBE5);
  // Text glow — warm golden glow around text
  static const Color roomTextGlow = Color(0x28C0A080);
  // Text shadow — soft warm shadow behind text
  static const Color roomTextShadow = Color(0x30A09080);

  // ── 3D Text on marble ──
  // Front face gradient (dark charcoal for contrast on marble)
  static const Color textFaceTop = Color(0xFF3A3530);
  static const Color textFaceBottom = Color(0xFF2A2520);
  // Side faces — medium warm grey
  static const Color textSide = Color(0xFF504840);
  // Text primary — rich dark for maximum contrast on marble
  static const Color textPrimary = Color(0xFF2E272A);

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

  static const RunThruTokens instance = RunThruTokens._();

  @override
  RunThruTokens copyWith() => this;

  @override
  RunThruTokens lerp(
    covariant ThemeExtension<RunThruTokens>? other,
    double t,
  ) =>
      this;
}
