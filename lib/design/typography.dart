import 'package:flutter/material.dart';
import 'package:speedy_boy/design/tokens.dart';

/// Typography system — all TextStyles sourced from here.
/// DM Sans for UI Shell, Space Mono for Reading Stage only.
class SpeedyBoyTypography {
  SpeedyBoyTypography._();

  // ── UI Shell (DM Sans) ──

  static const TextStyle display = TextStyle(
    fontFamily: 'DMSans',
    fontSize: 32,
    fontWeight: FontWeight.w600,
    height: 1.2,
    color: SpeedyBoyTokens.shellTextPrimary,
  );

  static const TextStyle title = TextStyle(
    fontFamily: 'DMSans',
    fontSize: 20,
    fontWeight: FontWeight.w500,
    height: 1.3,
    color: SpeedyBoyTokens.shellTextPrimary,
  );

  static const TextStyle body = TextStyle(
    fontFamily: 'DMSans',
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.5,
    color: SpeedyBoyTokens.shellTextPrimary,
  );

  static const TextStyle caption = TextStyle(
    fontFamily: 'DMSans',
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.4,
    color: SpeedyBoyTokens.shellTextSecondary,
  );

  static const TextStyle badge = TextStyle(
    fontFamily: 'DMSans',
    fontSize: 24,
    fontWeight: FontWeight.w600,
    height: 1.0,
    color: SpeedyBoyTokens.shellTextPrimary,
  );

  // ── Reading Stage (Space Mono) ──

  static TextStyle readingWord(double fontSize) => TextStyle(
        fontFamily: 'SpaceMono',
        fontSize: fontSize,
        fontWeight: FontWeight.w400,
        height: 1.0,
        color: SpeedyBoyTokens.stageText,
      );

  static TextStyle readingAnchor(double fontSize, {Color? color}) => TextStyle(
        fontFamily: 'SpaceMono',
        fontSize: fontSize,
        fontWeight: FontWeight.w700,
        height: 1.0,
        color: color ?? SpeedyBoyTokens.stageAnchor,
      );

  // ── Stage badge (WPM display on pause) ──

  static const TextStyle stageBadge = TextStyle(
    fontFamily: 'DMSans',
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.0,
    color: SpeedyBoyTokens.stageWpmBadge,
  );
}
