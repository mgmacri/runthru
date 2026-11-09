import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/design/tokens.dart';

// ignore_for_file: avoid_redundant_argument_values

/// Strict enforcement of every color value in RunThruTokens.
///
/// If a value here disagrees with the design spec, the spec wins — update
/// the token and this test together, never one without the other.
void main() {
  group('RunThruTokens — reading stage', () {
    test(
      'stageBase',
      () => expect(RunThruTokens.stageBase, const Color(0xFFEDE3D2)),
    );
    test(
      'stageLightShadow',
      () => expect(RunThruTokens.stageLightShadow, const Color(0xFFF4F5F0)),
    );
    test(
      'stageDarkShadow',
      () => expect(RunThruTokens.stageDarkShadow, const Color(0xFFDDD5C7)),
    );
    test(
      'stageText',
      () => expect(RunThruTokens.stageText, const Color(0xFF2E272A)),
    );
    test(
      'stageAnchor',
      () => expect(RunThruTokens.stageAnchor, const Color(0xFFC71F2D)),
    );
    test(
      'stageProgress',
      () => expect(RunThruTokens.stageProgress, const Color(0xFF149C88)),
    );
    test(
      'stagePauseOverlay',
      () => expect(RunThruTokens.stagePauseOverlay, const Color(0xCCD5D5D8)),
    );
    test(
      'stageWpmBadge',
      () => expect(RunThruTokens.stageWpmBadge, const Color(0xFF625D5D)),
    );
  });

  group('RunThruTokens — shell sand palette', () {
    test(
      'shellSandHi',
      () => expect(RunThruTokens.shellSandHi, const Color(0xFFE0D7C2)),
    );
    test(
      'shellSand',
      () => expect(RunThruTokens.shellSand, const Color(0xFFD6CCB4)),
    );
    test(
      'shellSandLo',
      () => expect(RunThruTokens.shellSandLo, const Color(0xFFCABFA6)),
    );
    test(
      'shellSandDeep',
      () => expect(RunThruTokens.shellSandDeep, const Color(0xFFC6BB9F)),
    );
    test(
      'shellCream',
      () => expect(RunThruTokens.shellCream, const Color(0xFFF3EEDE)),
    );
    test(
      'shellInk',
      () => expect(RunThruTokens.shellInk, const Color(0xFF332D22)),
    );
    test(
      'shellInkSample',
      () => expect(RunThruTokens.shellInkSample, const Color(0xFF443D2F)),
    );
    test(
      'shellInkSoft',
      () => expect(RunThruTokens.shellInkSoft, const Color(0xFF5C5546)),
    );
    test(
      'shellInkFaint',
      () => expect(RunThruTokens.shellInkFaint, const Color(0xFF665E50)),
    );
    test(
      'shellTeal',
      () => expect(RunThruTokens.shellTeal, const Color(0xFF46776B)),
    );
    test(
      'shellTealDeep',
      () => expect(RunThruTokens.shellTealDeep, const Color(0xFF3A665B)),
    );
    test(
      'shellTealTint',
      () => expect(RunThruTokens.shellTealTint, const Color(0x3346776B)),
    );
    test(
      'shellTealShadow',
      () => expect(RunThruTokens.shellTealShadow, const Color(0x553A665B)),
    );
    test(
      'shellTealHighlight',
      () => expect(RunThruTokens.shellTealHighlight, const Color(0x884F8A7C)),
    );
    test(
      'shellDivider',
      () => expect(RunThruTokens.shellDivider, const Color(0x66B8AC91)),
    );
    test(
      'shellStatusTint',
      () => expect(RunThruTokens.shellStatusTint, const Color(0x2A46776B)),
    );
  });

  group('RunThruTokens — shell compatibility aliases', () {
    test(
      'shellBase aliases shellSand',
      () => expect(RunThruTokens.shellBase, RunThruTokens.shellSand),
    );
    test(
      'shellLightShadow aliases shellCream',
      () => expect(RunThruTokens.shellLightShadow, RunThruTokens.shellCream),
    );
    test(
      'shellDarkShadow aliases shellSandDeep',
      () => expect(RunThruTokens.shellDarkShadow, RunThruTokens.shellSandDeep),
    );
    test(
      'shellTextPrimary aliases shellInk',
      () => expect(RunThruTokens.shellTextPrimary, RunThruTokens.shellInk),
    );
    test(
      'shellTextSecondary aliases shellInkSoft',
      () =>
          expect(RunThruTokens.shellTextSecondary, RunThruTokens.shellInkSoft),
    );
    test(
      'shellAccent aliases shellTeal',
      () => expect(RunThruTokens.shellAccent, RunThruTokens.shellTeal),
    );
  });

  group('RunThruTokens — shell semantic colors', () {
    test(
      'shellProcessing',
      () => expect(RunThruTokens.shellProcessing, const Color(0xFFFDAC53)),
    );
    test(
      'shellReady',
      () => expect(RunThruTokens.shellReady, const Color(0xFF149C88)),
    );
    test(
      'shellError',
      () => expect(RunThruTokens.shellError, const Color(0xFFED5656)),
    );
    test(
      'shellOnError',
      () => expect(RunThruTokens.shellOnError, const Color(0xFFF4F5F0)),
    );
  });

  group('RunThruTokens — 3D marble box', () {
    test(
      'cubeBase',
      () => expect(RunThruTokens.cubeBase, const Color(0xFFF5F0EA)),
    );
    test(
      'cubeBackWall',
      () => expect(RunThruTokens.cubeBackWall, const Color(0xFFEDE8E2)),
    );
    test(
      'cubeLeftWall',
      () => expect(RunThruTokens.cubeLeftWall, const Color(0xFFE8E0D8)),
    );
    test(
      'cubeRightWall',
      () => expect(RunThruTokens.cubeRightWall, const Color(0xFFE8E0D8)),
    );
    test(
      'cubeTopWall',
      () => expect(RunThruTokens.cubeTopWall, const Color(0xFFF0EBE5)),
    );
    test(
      'cubeBottomWall',
      () => expect(RunThruTokens.cubeBottomWall, const Color(0xFFE2DAD0)),
    );
    test(
      'cubeEdgeGlow',
      () => expect(RunThruTokens.cubeEdgeGlow, const Color(0xFFFAF7F4)),
    );
    test(
      'cubeAmbient',
      () => expect(RunThruTokens.cubeAmbient, const Color(0xFFF5F0EA)),
    );
    test(
      'cubeDirectional',
      () => expect(RunThruTokens.cubeDirectional, const Color(0xFFF8F4EE)),
    );
    test(
      'cubeNeuLight',
      () => expect(RunThruTokens.cubeNeuLight, const Color(0xFFFFFEFC)),
    );
    test(
      'cubeNeuDark',
      () => expect(RunThruTokens.cubeNeuDark, const Color(0xFFD5CCC0)),
    );
    test(
      'cubeRimShadow',
      () => expect(RunThruTokens.cubeRimShadow, const Color(0x20A09080)),
    );
  });

  group('RunThruTokens — marble interior', () {
    test(
      'marbleVeinPrimary',
      () => expect(RunThruTokens.marbleVeinPrimary, const Color(0xFFB8B0A8)),
    );
    test(
      'marbleVeinSecondary',
      () => expect(RunThruTokens.marbleVeinSecondary, const Color(0xFFD0C4B8)),
    );
    test(
      'marbleVeinHighlight',
      () => expect(RunThruTokens.marbleVeinHighlight, const Color(0x30FFFFFF)),
    );
    test(
      'marbleSurfaceGlow',
      () => expect(RunThruTokens.marbleSurfaceGlow, const Color(0x18F0E0D0)),
    );
    test(
      'roomGridLine',
      () => expect(RunThruTokens.roomGridLine, const Color(0xFFD0C8BE)),
    );
    test(
      'roomGridFar',
      () => expect(RunThruTokens.roomGridFar, const Color(0xFFE8E2DC)),
    );
    test(
      'roomBackground',
      () => expect(RunThruTokens.roomBackground, const Color(0xFFF2EDE7)),
    );
    test(
      'roomFog',
      () => expect(RunThruTokens.roomFog, const Color(0xFFF0EBE5)),
    );
    test(
      'roomTextGlow',
      () => expect(RunThruTokens.roomTextGlow, const Color(0x28C0A080)),
    );
    test(
      'roomTextShadow',
      () => expect(RunThruTokens.roomTextShadow, const Color(0x30A09080)),
    );
  });

  group('RunThruTokens — 3D text on marble', () {
    test(
      'textFaceTop',
      () => expect(RunThruTokens.textFaceTop, const Color(0xFF3A3530)),
    );
    test(
      'textFaceBottom',
      () => expect(RunThruTokens.textFaceBottom, const Color(0xFF2A2520)),
    );
    test(
      'textSide',
      () => expect(RunThruTokens.textSide, const Color(0xFF504840)),
    );
    test(
      'textPrimary',
      () => expect(RunThruTokens.textPrimary, const Color(0xFF2E272A)),
    );
  });

  group('RunThruTokens — pause overlay', () {
    test(
      'pauseWaveLineLight',
      () => expect(RunThruTokens.pauseWaveLineLight, const Color(0xFFB9AEC8)),
    );
    test(
      'pauseWaveLineMid',
      () => expect(RunThruTokens.pauseWaveLineMid, const Color(0xFF8D839E)),
    );
    test(
      'pauseWaveShadow',
      () => expect(RunThruTokens.pauseWaveShadow, const Color(0xFF342B38)),
    );
    test(
      'pauseBlindWashLight',
      () => expect(RunThruTokens.pauseBlindWashLight, const Color(0xFFCFC7DA)),
    );
    test(
      'pauseBlindWashDeep',
      () => expect(RunThruTokens.pauseBlindWashDeep, const Color(0xFFA59BB8)),
    );
  });

  group('RunThruTokens — anchor color palette', () {
    test('12 entries', () => expect(RunThruTokens.anchorColors.length, 12));
    test('12 names', () => expect(RunThruTokens.anchorColorNames.length, 12));

    final expected = [
      const Color(0xFFED5656), // Hot Coral
      const Color(0xFFFFA44A), // Blazing Orange
      const Color(0xFFFDAC53), // Marigold
      const Color(0xFFFBE337), // Buttercup
      const Color(0xFFF0E87D), // Limelight
      const Color(0xFFB5CF71), // Green Glow
      const Color(0xFF149C88), // Sea Green
      const Color(0xFF0078BE), // Brilliant Blue
      const Color(0xFF195190), // Turkish Sea
      const Color(0xFFD33479), // Fuscia Purple
      const Color(0xFFAD5E99), // Radiant Orchid
      const Color(0xFFC71F2D), // High Risk Red
    ];

    for (var i = 0; i < expected.length; i++) {
      test(
        'anchorColors[$i]',
        () => expect(RunThruTokens.anchorColors[i], expected[i]),
      );
    }

    const expectedNames = [
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

    for (var i = 0; i < expectedNames.length; i++) {
      test(
        'anchorColorNames[$i]',
        () => expect(RunThruTokens.anchorColorNames[i], expectedNames[i]),
      );
    }
  });
}
