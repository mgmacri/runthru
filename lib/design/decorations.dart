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

  /// Raised designer shell surface for prominent cards and bars.
  static BoxDecoration designerRaised({double borderRadius = 18}) {
    return BoxDecoration(
      color: RunThruTokens.shellSand,
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(color: RunThruTokens.shellSandHi, width: 0.6),
      boxShadow: const [
        BoxShadow(
          color: RunThruTokens.shellCream,
          offset: Offset(-6, -6),
          blurRadius: 14,
        ),
        BoxShadow(
          color: RunThruTokens.shellSandDeep,
          offset: Offset(7, 8),
          blurRadius: 16,
        ),
      ],
    );
  }

  /// Compact raised designer shell surface for dense rows and controls.
  static BoxDecoration designerRaisedSmall({double borderRadius = 12}) {
    return BoxDecoration(
      color: RunThruTokens.shellSand,
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(color: RunThruTokens.shellSandHi, width: 0.5),
      boxShadow: const [
        BoxShadow(
          color: RunThruTokens.shellCream,
          offset: Offset(-3, -3),
          blurRadius: 8,
        ),
        BoxShadow(
          color: RunThruTokens.shellSandDeep,
          offset: Offset(4, 5),
          blurRadius: 10,
        ),
      ],
    );
  }

  /// Inset designer shell surface for segmented controls and search fields.
  static BoxDecoration designerInset({double borderRadius = 14}) {
    return BoxDecoration(
      color: RunThruTokens.shellSandLo,
      borderRadius: BorderRadius.circular(borderRadius),
      boxShadow: const [
        BoxShadow(
          color: RunThruTokens.shellSandDeep,
          offset: Offset(3, 3),
          blurRadius: 8,
        ),
        BoxShadow(
          color: RunThruTokens.shellCream,
          offset: Offset(-3, -3),
          blurRadius: 8,
        ),
      ],
    );
  }

  /// Flat designer shell surface for grouped content bands.
  static BoxDecoration designerFlat({double borderRadius = 12}) {
    return BoxDecoration(
      color: RunThruTokens.shellSandHi.withValues(alpha: 0.36),
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(color: RunThruTokens.shellDivider, width: 0.6),
    );
  }

  /// Teal primary-action decoration.
  static BoxDecoration tealButton({double borderRadius = 12}) {
    return BoxDecoration(
      color: RunThruTokens.shellTealDeep,
      borderRadius: BorderRadius.circular(borderRadius),
      boxShadow: const [
        BoxShadow(
          color: RunThruTokens.shellTealShadow,
          offset: Offset(0, 6),
          blurRadius: 12,
        ),
        BoxShadow(
          color: RunThruTokens.shellTealHighlight,
          offset: Offset(-2, -2),
          blurRadius: 6,
        ),
      ],
    );
  }

  /// Small square thumbnail decoration for source and document icons.
  static BoxDecoration iconThumb({double borderRadius = 10}) {
    return BoxDecoration(
      color: RunThruTokens.shellTeal,
      borderRadius: BorderRadius.circular(borderRadius),
      boxShadow: const [
        BoxShadow(
          color: RunThruTokens.shellSandDeep,
          offset: Offset(2, 3),
          blurRadius: 8,
        ),
      ],
    );
  }

  /// Rounded status-pill decoration.
  static BoxDecoration statusPill({bool emphasized = false}) {
    return BoxDecoration(
      color: emphasized
          ? RunThruTokens.shellTealTint
          : RunThruTokens.shellSandHi.withValues(alpha: 0.42),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(
        color: emphasized
            ? RunThruTokens.shellTeal.withValues(alpha: 0.28)
            : RunThruTokens.shellDivider,
        width: 0.6,
      ),
    );
  }

  /// Hairline divider used between dense grouped rows.
  static Border rowDivider() {
    return const Border(
      top: BorderSide(color: RunThruTokens.shellDivider, width: 0.6),
    );
  }
}
