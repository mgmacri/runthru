import 'package:flutter/material.dart';
import 'package:runthru/design/tokens.dart';

enum RunThruSurface { stage, shell }

enum RunThruShadowSize { small, standard, large }

class RunThruDecorations {
  RunThruDecorations._();

  static const Map<RunThruShadowSize, ({double offset, double blur})>
      _shadowSpecs = {
    RunThruShadowSize.small: (offset: 4, blur: 8),
    RunThruShadowSize.standard: (offset: 6, blur: 12),
    RunThruShadowSize.large: (offset: 10, blur: 20),
  };

  static BoxDecoration raisedDecoration(
    RunThruSurface surface, {
    RunThruShadowSize size = RunThruShadowSize.standard,
    double borderRadius = 16,
  }) {
    final spec = _shadowSpecs[size]!;
    final Color base;
    final Color light;
    final Color dark;

    switch (surface) {
      case RunThruSurface.stage:
        base = RunThruTokens.stageBase;
        light = RunThruTokens.stageLightShadow;
        dark = RunThruTokens.stageDarkShadow;
      case RunThruSurface.shell:
        base = RunThruTokens.shellBase;
        light = RunThruTokens.shellLightShadow;
        dark = RunThruTokens.shellDarkShadow;
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
    RunThruSurface surface, {
    RunThruShadowSize size = RunThruShadowSize.standard,
    double borderRadius = 16,
  }) {
    final spec = _shadowSpecs[size]!;
    final Color base;
    final Color light;
    final Color dark;

    switch (surface) {
      case RunThruSurface.stage:
        base = RunThruTokens.stageBase;
        light = RunThruTokens.stageLightShadow;
        dark = RunThruTokens.stageDarkShadow;
      case RunThruSurface.shell:
        base = RunThruTokens.shellBase;
        light = RunThruTokens.shellLightShadow;
        dark = RunThruTokens.shellDarkShadow;
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

  static BoxDecoration pillDecoration(RunThruSurface surface) {
    return raisedDecoration(
      surface,
      size: RunThruShadowSize.small,
      borderRadius: 999,
    );
  }
}
