import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/features/reading/pacing/pacing_config.dart';
import 'package:runthru/features/reading/pacing/word_duration.dart';

/// Test helper mirroring the C++ `duration(wpm, word, next)` signature.
int duration(
  int wpm,
  String word,
  String? next, {
  PacingConfig config = defaultPacingConfig,
}) {
  return durationForWord(
    word,
    nextWord: next,
    baseIntervalMs: (60000 / wpm).round(),
    config: config,
  );
}

void main() {
  // -------------------------------------------------------------------------
  // Duration: no bonus
  // -------------------------------------------------------------------------
  group('Duration: no bonus', () {
    test('short word no bonus', () {
      // "a" → 1 readable char, 1 syllable, no punctuation → base only
      expect(duration(300, 'a', 'b'), 200);
    });
  });

  // -------------------------------------------------------------------------
  // Duration: punctuation pauses
  // -------------------------------------------------------------------------
  group('Duration: punctuation pauses', () {
    test('comma pause', () {
      // "hi," → comma → +45% → 200 + 90 = 290
      expect(duration(300, 'hi,', 'there'), 290);
    });

    test('sentence pause', () {
      // "done." next "The" (uppercase) → sentence +135% → 200 + 270 = 470
      expect(duration(300, 'done.', 'The'), 470);
    });

    test('strong sentence pause', () {
      // "yes!" → strong sentence +150% → 200 + 300 = 500
      expect(duration(300, 'yes!', 'The'), 500);
    });

    test('sentence pause preserved with closing quote', () {
      expect(duration(300, '"done."', 'The'), 470);
    });

    test('sentence pause preserved with closing parenthesis', () {
      expect(duration(300, '(done.)', 'The'), 470);
    });

    test('clause pause semicolon', () {
      // "thus;" → clause +80% → 200 + 160 = 360
      expect(duration(300, 'thus;', 'the'), 360);
    });

    test('dash pause', () {
      // "so-" trailing dash → +60% → 200 + 120 = 320
      expect(duration(300, 'so-', 'the'), 320);
    });

    test('ellipsis pause', () {
      // "and..." → ellipsis +110% → 200 + 220 = 420
      expect(duration(300, 'and...', 'then'), 420);
    });
  });

  // -------------------------------------------------------------------------
  // Duration: abbreviation suppresses sentence pause
  // -------------------------------------------------------------------------
  group('Duration: abbreviation suppresses sentence pause', () {
    test('known abbreviation no pause', () {
      // "Mr." is in kKnownAbbreviations → no punctuation bonus
      expect(duration(300, 'Mr.', 'Smith'), 200);
    });

    test('dotted initialism no pause', () {
      // "U.S." → isDottedInitialism → no punctuation pause
      // but allCaps(+14%) + techConnector(+8%) = 22% complexity+length
      // length: techConnectors=1 > joiners=0 → (1-0)*8 = 8%
      // complexity: uppercase=2, letters=2, uppercaseCount==letterCount → +14%
      // scaledDelayMs(scaledPercent(8,100), 200) = (8*200)/100 = 16
      // scaledDelayMs(scaledPercent(14,100), 200) = (14*200)/100 = 28
      // total = 200 + 16 + 28 = 244
      expect(duration(300, 'U.S.', 'The'), 244);
    });

    test('short word period no pause', () {
      // "it." next "was" (lowercase) → readable=2 ≤ 4 and next starts
      // lowercase → abbreviation → no pause
      expect(duration(300, 'it.', 'was'), 200);
    });

    test('accented lowercase next word suppresses sentence pause', () {
      // "done." next "élan" (é = U+00E9, lowercase) → suppresses sentence
      expect(duration(300, 'done.', '\u00E9lan'), 200);
    });

    test('extended Latin lowercase next word suppresses sentence pause', () {
      // "done." next "œuvre" (œ = U+0153, lowercase) → suppresses
      expect(duration(300, 'done.', '\u0153uvre'), 200);
    });

    test('extended Latin uppercase next word keeps sentence pause', () {
      // "done." next "Œuvre" (Œ = U+0152, uppercase) → keeps +135%
      expect(duration(300, 'done.', '\u0152uvre'), 470);
    });

    test('Baltic lowercase next word suppresses sentence pause', () {
      // "done." next "ātrums" (ā = U+0101, lowercase) → suppresses
      expect(duration(300, 'done.', '\u0101trums'), 200);
    });

    test('Czech lowercase next word suppresses sentence pause', () {
      // "done." next "ěra" (ě = U+011B, lowercase) → suppresses
      expect(duration(300, 'done.', '\u011Bra'), 200);
    });

    test('sentence pause not suppressed for long word', () {
      // "chapter." next "The" (uppercase) → readable=7 > 4,
      // not a known abbreviation → sentence pause
      // length bonus: readable=7, tier1 extra=1 → 1*6=6%
      // syllables: c,h,a(1),p,t,e(2),r → lettersOnly="chapter"
      // ends 'r' → no silent-e. groups=2 ≤ 2, no syllable bonus.
      // total = 6% + 135% → scaled: 12 + 270 = 282 → 200 + 282 = 482
      expect(duration(300, 'chapter.', 'The'), 482);
    });
  });

  // -------------------------------------------------------------------------
  // Duration: length bonus
  // -------------------------------------------------------------------------
  group('Duration: length bonus', () {
    test('long word length bonus', () {
      // "strength" → readable=8. tier1 extra=8-6=2 → 12%.
      // syllables: s,t,r,e(1),n,g,t,h → groups=1, no bonus.
      // total = 12% → 200 + 24 = 224
      expect(duration(300, 'strength', 'and'), 224);
    });

    test('accented Latin word counts as readable', () {
      // "café" (é = U+00E9) → readable=4, ≤ 6 → no bonus
      expect(duration(300, 'caf\u00E9', 'et'), 200);
    });

    test('extended Latin word counts as readable', () {
      // "łodz" (ł = U+0142) → readable=4, ≤ 6 → no bonus
      expect(duration(300, '\u0142odz', 'ma'), 200);
    });

    test('Baltic custom vowel affects syllable bonus', () {
      // "ākula" (ā = U+0101) → 3 vowel groups (ā,u,a) → +10% complexity
      // 200 + 20 = 220
      expect(duration(300, '\u0101kula', 'ir'), 220);
    });

    test('Czech extended word counts as readable', () {
      // "běh" (ě = U+011B) → readable=3, ≤ 6 → no bonus
      expect(duration(300, 'b\u011Bh', 'a'), 200);
    });

    test('Hungarian double acute vowel affects syllable bonus', () {
      // "ővoda" (ő = U+0151) → 3 vowel groups (ő,o,a) → +10% complexity
      // 200 + 20 = 220
      expect(duration(300, '\u0151voda', 'van'), 220);
    });

    test('Sami custom letter counts as readable', () {
      // "ŧahti" (ŧ = U+0167) → readable=5, ≤ 6 → no bonus
      // syllables: ŧ(not vowel),a(1),h,t,i(2) → groups=2, ≤ 2 → no bonus
      expect(duration(300, '\u0167ahti', 'ja'), 200);
    });

    test('very long word extra tier', () {
      // "information" → readable=11.
      // tier1 extra=5→30%, tier2 extra=1→9%. length=39%.
      // syllables: i(1),n,f,o(2),r,m,a(3),t,i(4),o(skip prev=vowel),n
      // groups=4. syllableBonus: (4-2)*10=20%.
      // total = 39% + 20% = 59%
      // scaledDelayMs(scaledPercent(39,100), 200) = (39*200)/100 = 78
      // scaledDelayMs(scaledPercent(20,100), 200) = (20*200)/100 = 40
      // 200 + 78 + 40 = 318
      expect(duration(300, 'information', 'is'), 318);
    });
  });

  // -------------------------------------------------------------------------
  // Duration: compound/technical word bonus
  // -------------------------------------------------------------------------
  group('Duration: compound/technical word bonus', () {
    test('compound word bonus', () {
      // "well-known" → readable=9 (w,e,l,l,k,n,o,w,n).
      // joinerCount=1 ('-' between 'l' and 'k').
      // tier1 extra=9-6=3 → 18%. joiner: +14%. readable<10, no longCompound.
      // techConnectorCount=1 == joinerCount → no extra tech bonus.
      // length bonus = min(170, 18+14) = 32%.
      // syllables: w,e(1),l,l,-→reset,k,n,o(2),w,n. groups=2. ≤2, no bonus.
      // complexity=0%. No punctuation.
      // total = 32% → (32*200)/100 = 64 → 200 + 64 = 264
      expect(duration(300, 'well-known', 'and'), 264);
    });
  });

  // -------------------------------------------------------------------------
  // Duration: all-caps complexity
  // -------------------------------------------------------------------------
  group('Duration: all-caps complexity', () {
    test('all caps complexity', () {
      // "NASA" → uppercase=4, letters=4, uppercase==letters → allCaps +14%.
      // readable=4, no length bonus. No digits. No tech connectors.
      // complexity = 14%. No punctuation.
      // total = 14% → (14*200)/100 = 28 → 200 + 28 = 228
      expect(duration(300, 'NASA', 'sent'), 228);
    });
  });

  // -------------------------------------------------------------------------
  // Duration: pacing scale affects bonus magnitude
  // -------------------------------------------------------------------------
  group('Duration: pacing scale affects bonus magnitude', () {
    test('punctuation scale halved', () {
      // "done." next "The", punctuationScale=50
      // sentencePause=135, scaled: (135*50)/100 = 67. total=67%
      // scaledDelayMs(67, 200) = (67*200)/100 = 134
      // 200 + 134 = 334
      expect(
        duration(
          300,
          'done.',
          'The',
          config: const PacingConfig(punctuationScalePercent: 50),
        ),
        334,
      );
    });

    test('length scale zero equivalent (clamped at 25)', () {
      // scale clamped at 25 minimum, so longWordScale=0 → treated as 25
      // "strength" length bonus=12%, scaled by 25 → (12*25)/100=3%.
      // scaledDelayMs(3, 200) = (3*200)/100 = 6
      // total = 200 + 6 = 206
      expect(
        duration(
          300,
          'strength',
          'and',
          config: const PacingConfig(longWordScalePercent: 0),
        ),
        206,
      );
    });
  });

  // -------------------------------------------------------------------------
  // Helper unit tests (exposed via @visibleForTesting)
  // -------------------------------------------------------------------------
  group('Helper: character classification', () {
    test('startsWithLowercaseLetter detects ASCII lowercase', () {
      expect(startsWithLowercaseLetter('the'), true);
      expect(startsWithLowercaseLetter('The'), false);
    });

    test('startsWithLowercaseLetter detects accented Latin', () {
      expect(startsWithLowercaseLetter('\u00E9lan'), true); // élan
    });

    test('startsWithLowercaseLetter detects extended Latin lowercase', () {
      expect(startsWithLowercaseLetter('\u0153uvre'), true); // œuvre
      expect(startsWithLowercaseLetter('\u0101trums'), true); // ātrums
      expect(startsWithLowercaseLetter('\u011Bra'), true); // ěra
    });

    test('startsWithLowercaseLetter rejects extended Latin uppercase', () {
      expect(startsWithLowercaseLetter('\u0152uvre'), false); // Œuvre
    });

    test('startsWithLowercaseLetter handles null and empty', () {
      expect(startsWithLowercaseLetter(null), false);
      expect(startsWithLowercaseLetter(''), false);
    });
  });

  group('Helper: readable character count', () {
    test('counts letters and digits', () {
      expect(readableCharacterCount('hello'), 5);
      expect(readableCharacterCount('U.S.'), 2);
      expect(readableCharacterCount('hi,'), 2);
      expect(readableCharacterCount('caf\u00E9'), 4);
    });
  });

  group('Helper: syllable groups', () {
    test('single vowel word', () {
      expect(approximateSyllableGroups('cat'), 1);
    });

    test('silent-e decrement', () {
      // "done" → d,o(1),n,e(2) → lettersOnly="done" ends 'e',
      // not 'le'/'ye', groups>1, letterCount>3 → decrement → 1
      expect(approximateSyllableGroups('done'), 1);
    });

    test('multi-syllable word', () {
      // "information" → 4 groups
      expect(approximateSyllableGroups('information'), 4);
    });

    test('extended Latin vowels count', () {
      // "ākula" → ā(1),k,u(2),l,a(3) → 3 groups
      expect(approximateSyllableGroups('\u0101kula'), 3);
    });

    test('hyphen resets previous vowel state', () {
      // "well-known" → w,e(1),l,l,-(reset),k,n,o(2),w,n → 2 groups
      expect(approximateSyllableGroups('well-known'), 2);
    });
  });

  // -------------------------------------------------------------------------
  // PacingConfig tests
  // -------------------------------------------------------------------------
  group('PacingConfig', () {
    test('default values', () {
      const config = PacingConfig();
      expect(config.longWordDelayMs, 200);
      expect(config.complexWordDelayMs, 200);
      expect(config.punctuationDelayMs, 200);
      expect(config.longWordScalePercent, 100);
      expect(config.complexWordScalePercent, 100);
      expect(config.punctuationScalePercent, 100);
    });

    test('clamps delay above maximum', () {
      const config = PacingConfig(longWordDelayMs: 9999);
      expect(config.longWordDelayMs, 600);
    });

    test('clamps delay below minimum', () {
      const config = PacingConfig(complexWordDelayMs: -5);
      expect(config.complexWordDelayMs, 0);
    });

    test('clamps scale below minimum', () {
      const config = PacingConfig(longWordScalePercent: 0);
      expect(config.longWordScalePercent, 25);
    });

    test('clamps scale above maximum', () {
      const config = PacingConfig(punctuationScalePercent: 300);
      expect(config.punctuationScalePercent, 200);
    });

    test('equality', () {
      const a = PacingConfig(longWordDelayMs: 150);
      const b = PacingConfig(longWordDelayMs: 150);
      const c = PacingConfig(longWordDelayMs: 200);
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });

    test('hashCode consistency', () {
      const a = PacingConfig(longWordDelayMs: 150);
      const b = PacingConfig(longWordDelayMs: 150);
      expect(a.hashCode, b.hashCode);
    });

    test('copyWith', () {
      const original = PacingConfig();
      final modified = original.copyWith(longWordScalePercent: 150);
      expect(modified.longWordScalePercent, 150);
      expect(modified.complexWordScalePercent, 100);
    });

    test('JSON round-trip', () {
      const config = PacingConfig(
        longWordDelayMs: 300,
        complexWordDelayMs: 400,
        punctuationDelayMs: 100,
        longWordScalePercent: 75,
        complexWordScalePercent: 150,
        punctuationScalePercent: 200,
      );
      final json = config.toJson();
      final restored = PacingConfig.fromJson(json);
      expect(restored, equals(config));
    });

    test('fromJson handles missing keys gracefully', () {
      final config = PacingConfig.fromJson({});
      expect(config, equals(defaultPacingConfig));
    });

    test('defaultPacingConfig produces no bonus for plain words', () {
      // With default config, a word with no bonuses returns exactly base
      final result = durationForWord(
        'the',
        nextWord: 'cat',
        baseIntervalMs: 200,
        config: defaultPacingConfig,
      );
      expect(result, 200);
    });
  });
}
