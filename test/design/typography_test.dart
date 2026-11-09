import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/design/tokens.dart';
import 'package:runthru/design/typography.dart';

// ignore_for_file: avoid_redundant_argument_values

/// Strict enforcement of every TextStyle in RunThruTypography.
///
/// If a value here disagrees with the design spec, update the style and
/// this test together, never one without the other.
void main() {
  group('RunThruTypography — font constant', () {
    test('uiFamily is HankenGrotesk', () {
      expect(RunThruTypography.uiFamily, 'HankenGrotesk');
    });
  });

  group('RunThruTypography — shell styles', () {
    test('display', () {
      const s = RunThruTypography.display;
      expect(s.fontFamily, 'HankenGrotesk');
      expect(s.fontSize, 32);
      expect(s.fontWeight, FontWeight.w600);
      expect(s.height, 1.2);
      expect(s.color, RunThruTokens.shellTextPrimary);
    });

    test('title', () {
      const s = RunThruTypography.title;
      expect(s.fontFamily, 'HankenGrotesk');
      expect(s.fontSize, 20);
      expect(s.fontWeight, FontWeight.w500);
      expect(s.height, 1.3);
      expect(s.color, RunThruTokens.shellTextPrimary);
    });

    test('body', () {
      const s = RunThruTypography.body;
      expect(s.fontFamily, 'HankenGrotesk');
      expect(s.fontSize, 16);
      expect(s.fontWeight, FontWeight.w400);
      expect(s.height, 1.5);
      expect(s.color, RunThruTokens.shellTextPrimary);
    });

    test('caption', () {
      const s = RunThruTypography.caption;
      expect(s.fontFamily, 'HankenGrotesk');
      expect(s.fontSize, 12);
      expect(s.fontWeight, FontWeight.w400);
      expect(s.height, 1.4);
      expect(s.color, RunThruTokens.shellTextSecondary);
    });

    test('badge', () {
      const s = RunThruTypography.badge;
      expect(s.fontFamily, 'HankenGrotesk');
      expect(s.fontSize, 24);
      expect(s.fontWeight, FontWeight.w600);
      expect(s.height, 1.0);
      expect(s.color, RunThruTokens.shellTextPrimary);
    });

    test('screenTitle', () {
      const s = RunThruTypography.screenTitle;
      expect(s.fontFamily, 'HankenGrotesk');
      expect(s.fontSize, 23);
      expect(s.fontWeight, FontWeight.w700);
      expect(s.height, 1.08);
      expect(s.color, RunThruTokens.shellInk);
    });

    test('sectionLabel', () {
      const s = RunThruTypography.sectionLabel;
      expect(s.fontFamily, 'HankenGrotesk');
      expect(s.fontSize, 12);
      expect(s.fontWeight, FontWeight.w700);
      expect(s.height, 1.25);
      expect(s.color, RunThruTokens.shellInkSoft);
    });

    test('rowTitle', () {
      const s = RunThruTypography.rowTitle;
      expect(s.fontFamily, 'HankenGrotesk');
      expect(s.fontSize, 15);
      expect(s.fontWeight, FontWeight.w700);
      expect(s.height, 1.22);
      expect(s.color, RunThruTokens.shellInk);
    });

    test('metadata', () {
      const s = RunThruTypography.metadata;
      expect(s.fontFamily, 'Satoshi');
      expect(s.fontSize, 12);
      expect(s.fontWeight, FontWeight.w500);
      expect(s.height, 1.28);
      expect(s.color, RunThruTokens.shellInkSoft);
    });

    test('tinyLabel', () {
      const s = RunThruTypography.tinyLabel;
      expect(s.fontFamily, 'Satoshi');
      expect(s.fontSize, 10);
      expect(s.fontWeight, FontWeight.w700);
      expect(s.height, 1.15);
      expect(s.color, RunThruTokens.shellInkSoft);
    });

    test('primaryButton', () {
      const s = RunThruTypography.primaryButton;
      expect(s.fontFamily, 'HankenGrotesk');
      expect(s.fontSize, 15);
      expect(s.fontWeight, FontWeight.w700);
      expect(s.height, 1.1);
      expect(s.color, RunThruTokens.shellCream);
    });

    test('navLabel', () {
      const s = RunThruTypography.navLabel;
      expect(s.fontFamily, 'Satoshi');
      expect(s.fontSize, 11);
      expect(s.fontWeight, FontWeight.w700);
      expect(s.height, 1.12);
      expect(s.color, RunThruTokens.shellInkSoft);
    });

    test('statusPill', () {
      const s = RunThruTypography.statusPill;
      expect(s.fontFamily, 'Satoshi');
      expect(s.fontSize, 11);
      expect(s.fontWeight, FontWeight.w700);
      expect(s.height, 1.1);
      expect(s.color, RunThruTokens.shellTealDeep);
    });
  });

  group('RunThruTypography — stage styles', () {
    test('stageBadge', () {
      const s = RunThruTypography.stageBadge;
      expect(s.fontFamily, 'HankenGrotesk');
      expect(s.fontSize, 14);
      expect(s.fontWeight, FontWeight.w500);
      expect(s.height, 1.0);
      expect(s.color, RunThruTokens.stageWpmBadge);
    });

    test('readingWord defaults', () {
      final s = RunThruTypography.readingWord(24);
      expect(s.fontFamily, 'HankenGrotesk');
      expect(s.fontSize, 24);
      expect(s.fontWeight, FontWeight.w400);
      expect(s.height, 1.0);
      expect(s.color, RunThruTokens.stageText);
    });

    test('readingWord respects color override', () {
      final s = RunThruTypography.readingWord(
        24,
        color: RunThruTokens.stageAnchor,
      );
      expect(s.color, RunThruTokens.stageAnchor);
    });

    test('readingWord respects fontFamily override', () {
      final s = RunThruTypography.readingWord(24, fontFamily: 'Georgia');
      expect(s.fontFamily, 'Georgia');
    });

    test('readingAnchor defaults', () {
      final s = RunThruTypography.readingAnchor(24);
      expect(s.fontFamily, 'HankenGrotesk');
      expect(s.fontSize, 24);
      expect(s.fontWeight, FontWeight.w700);
      expect(s.height, 1.0);
      expect(s.color, RunThruTokens.stageAnchor);
    });

    test('readingAnchor respects color override', () {
      final s = RunThruTypography.readingAnchor(
        24,
        color: RunThruTokens.stageText,
      );
      expect(s.color, RunThruTokens.stageText);
    });

    test('readingAnchor respects fontFamily override', () {
      final s = RunThruTypography.readingAnchor(24, fontFamily: 'Georgia');
      expect(s.fontFamily, 'Georgia');
    });
  });

  group('RunThruTypography — availableFonts', () {
    test('AtkinsonHyperlegible is bundled and first', () {
      expect(
        RunThruTypography.availableFonts.first.family,
        'AtkinsonHyperlegible',
      );
      expect(RunThruTypography.availableFonts.first.isBundled, isTrue);
    });

    test('HankenGrotesk is bundled and second', () {
      expect(RunThruTypography.availableFonts[1].family, 'HankenGrotesk');
      expect(RunThruTypography.availableFonts[1].isBundled, isTrue);
    });

    test('BricolageGrotesque and Satoshi are bundled', () {
      expect(RunThruTypography.availableFonts[2].family, 'BricolageGrotesque');
      expect(RunThruTypography.availableFonts[2].isBundled, isTrue);
      expect(RunThruTypography.availableFonts[3].family, 'Satoshi');
      expect(RunThruTypography.availableFonts[3].isBundled, isTrue);
    });

    test('all system fonts are not bundled', () {
      final system = RunThruTypography.availableFonts.skip(4);
      expect(system.every((f) => !f.isBundled), isTrue);
    });

    test('no duplicate families', () {
      final families = RunThruTypography.availableFonts
          .map((f) => f.family)
          .toList();
      expect(families.toSet().length, families.length);
    });
  });
}
