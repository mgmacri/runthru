import 'package:flutter/material.dart';
import 'package:speedy_boy/design/tokens.dart';

enum SpeedyBoySurface { stage, shell }

enum SpeedyBoyShadowSize { small, standard, large }

class SpeedyBoyDecorations {
  SpeedyBoyDecorations._();

  static const Map<SpeedyBoyShadowSize, ({double offset, double blur})>
      _shadowSpecs = {
    SpeedyBoyShadowSize.small: (offset: 4, blur: 8),
    SpeedyBoyShadowSize.standard: (offset: 6, blur: 12),
    SpeedyBoyShadowSize.large: (offset: 10, blur: 20),
  };

  static BoxDecoration raisedDecoration(
    SpeedyBoySurface surface, {
    SpeedyBoyShadowSize size = SpeedyBoyShadowSize.standard,
    double borderRadius = 16,
  }) {
    final spec = _shadowSpecs[size]!;
    final Color base;
    final Color light;
    final Color dark;

    switch (surface) {
      case SpeedyBoySurface.stage:
        base = SpeedyBoyTokens.stageBase;
        light = SpeedyBoyTokens.stageLightShadow;
        dark = SpeedyBoyTokens.stageDarkShadow;
      case SpeedyBoySurface.shell:
        base = SpeedyBoyTokens.shellBase;
        light = SpeedyBoyTokens.shellLightShadow;
        dark = SpeedyBoyTokens.shellDarkShadow;
    }

    return BoxDecoration(
      color: base,
      borderRadius: BorderRadius.circular(borderRadius),
      boxShadow: [
        BoxShadow(
          color: light,
          offset: Offset(-spec.offset, -spec.offset),
          blurRadius: spec.blur,
        ),
        BoxShadow(
          color: dark,
          offset: Offset(spec.offset, spec.offset),
          blurRadius: spec.blur,
        ),
      ],
    );
  }

  static BoxDecoration insetDecoration(
    SpeedyBoySurface surface, {
    SpeedyBoyShadowSize size = SpeedyBoyShadowSize.standard,
    double borderRadius = 16,
  }) {
    final spec = _shadowSpecs[size]!;
    final Color base;
    final Color light;
    final Color dark;

    switch (surface) {
      case SpeedyBoySurface.stage:
        base = SpeedyBoyTokens.stageBase;
        light = SpeedyBoyTokens.stageLightShadow;
        dark = SpeedyBoyTokens.stageDarkShadow;
      case SpeedyBoySurface.shell:
        base = SpeedyBoyTokens.shellBase;
        light = SpeedyBoyTokens.shellLightShadow;
        dark = SpeedyBoyTokens.shellDarkShadow;
    }

    // Inset: reversed shadow directions
    return BoxDecoration(
      color: base,
      borderRadius: BorderRadius.circular(borderRadius),
      boxShadow: [
        BoxShadow(
          color: dark,
          offset: Offset(-spec.offset, -spec.offset),
          blurRadius: spec.blur,
        ),
        BoxShadow(
          color: light,
          offset: Offset(spec.offset, spec.offset),
          blurRadius: spec.blur,
        ),
      ],
    );
  }

  static BoxDecoration pillDecoration(SpeedyBoySurface surface) {
    return raisedDecoration(
      surface,
      size: SpeedyBoyShadowSize.small,
      borderRadius: 999,
    );
  }
}
