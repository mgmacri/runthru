import 'package:flutter/material.dart';
import 'package:speedy_boy/design/tokens.dart';

/// Typography system — all TextStyles sourced from here.
/// Bricolage Grotesque for UI shell. Reading stage font is user-selectable.
class SpeedyBoyTypography {
  SpeedyBoyTypography._();

  /// Default UI font.
  static const String _uiFamily = 'BricolageGrotesque';

  // ── UI Shell ──

  static const TextStyle display = TextStyle(
    fontFamily: _uiFamily,
    fontSize: 32,
    fontWeight: FontWeight.w600,
    height: 1.2,
    color: SpeedyBoyTokens.shellTextPrimary,
  );

  static const TextStyle title = TextStyle(
    fontFamily: _uiFamily,
    fontSize: 20,
    fontWeight: FontWeight.w500,
    height: 1.3,
    color: SpeedyBoyTokens.shellTextPrimary,
  );

  static const TextStyle body = TextStyle(
    fontFamily: _uiFamily,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.5,
    color: SpeedyBoyTokens.shellTextPrimary,
  );

  static const TextStyle caption = TextStyle(
    fontFamily: _uiFamily,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.4,
    color: SpeedyBoyTokens.shellTextSecondary,
  );

  static const TextStyle badge = TextStyle(
    fontFamily: _uiFamily,
    fontSize: 24,
    fontWeight: FontWeight.w600,
    height: 1.0,
    color: SpeedyBoyTokens.shellTextPrimary,
  );

  // ── Reading Stage (user-selectable font) ──

  static TextStyle readingWord(
    double fontSize, {
    Color? color,
    String fontFamily = _uiFamily,
  }) =>
      TextStyle(
        fontFamily: fontFamily,
        fontSize: fontSize,
        fontWeight: FontWeight.w400,
        height: 1.0,
        color: color ?? SpeedyBoyTokens.stageText,
      );

  static TextStyle readingAnchor(
    double fontSize, {
    Color? color,
    String fontFamily = _uiFamily,
  }) =>
      TextStyle(
        fontFamily: fontFamily,
        fontSize: fontSize,
        fontWeight: FontWeight.w700,
        height: 1.0,
        color: color ?? SpeedyBoyTokens.stageAnchor,
      );

  // ── Stage badge (WPM display on pause) ──

  static const TextStyle stageBadge = TextStyle(
    fontFamily: _uiFamily,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.0,
    color: SpeedyBoyTokens.stageWpmBadge,
  );

  /// All available reading font choices. Bundled fonts first, then system fonts.
  static const List<FontChoice> availableFonts = [
    // ── Bundled fonts ──
    FontChoice('BricolageGrotesque', 'Bricolage Grotesque', true),
    FontChoice('Satoshi', 'Satoshi', true),
    // ── System fonts ──
    FontChoice('Arial', 'Arial', false),
    FontChoice('Helvetica Neue', 'Helvetica Neue', false),
    FontChoice('Helvetica', 'Helvetica', false),
    FontChoice('San Francisco', 'SF Pro', false),
    FontChoice('Segoe UI', 'Segoe UI', false),
    FontChoice('Roboto', 'Roboto', false),
    FontChoice('Inter', 'Inter', false),
    FontChoice('Georgia', 'Georgia', false),
    FontChoice('Times New Roman', 'Times New Roman', false),
    FontChoice('Palatino', 'Palatino', false),
    FontChoice('Garamond', 'Garamond', false),
    FontChoice('Courier New', 'Courier New', false),
    FontChoice('Consolas', 'Consolas', false),
    FontChoice('SF Mono', 'SF Mono', false),
    FontChoice('Verdana', 'Verdana', false),
    FontChoice('Trebuchet MS', 'Trebuchet MS', false),
    FontChoice('Futura', 'Futura', false),
    FontChoice('Gill Sans', 'Gill Sans', false),
    FontChoice('Optima', 'Optima', false),
    FontChoice('Avenir', 'Avenir', false),
    FontChoice('Avenir Next', 'Avenir Next', false),
  ];
}

/// A font option available to the user.
class FontChoice {
  const FontChoice(this.family, this.displayName, this.isBundled);

  /// Font family name as used in TextStyle.
  final String family;

  /// Human-friendly display name.
  final String displayName;

  /// Whether this font is bundled (vs system font that may not be present).
  final bool isBundled;
}
