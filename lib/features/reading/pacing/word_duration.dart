/// Per-word display duration model.
///
/// Algorithm constants and tier thresholds derived from RSVP Nano
/// (ionutdecebal/rsvpnano, MIT). See NOTICE for attribution.
///
/// Pure function; safe to call on any isolate.
library;

import 'package:runthru/features/reading/pacing/pacing_config.dart';

// ---------------------------------------------------------------------------
// Algorithm constants (verified from C++ source ReadingLoop.cpp)
// ---------------------------------------------------------------------------

const int _kLongWordAfterChars = 6;
const int _kLongWordPercentPerChar = 6;
const int _kVeryLongWordAfterChars = 10;
const int _kVeryLongWordPercentPerChar = 9;
const int _kUltraLongWordAfterChars = 14;
const int _kUltraLongWordPercentPerChar = 12;
const int _kLongWordMaxPercent = 170;
const int _kCompoundJoinerPercent = 14;
const int _kLongCompoundWordPercent = 18;
const int _kTechnicalConnectorPercent = 8;

const int _kSyllableBonusAfterCount = 2;
const int _kSyllableBonusPercentPerGroup = 10;
const int _kSyllableBonusMaxPercent = 50;
const int _kAllCapsComplexityPercent = 14;
const int _kMixedTokenComplexityPercent = 22;
const int _kNumericTokenComplexityPercent = 10;
const int _kDenseConnectorComplexityPercent = 12;
const int _kComplexWordMaxPercent = 85;

const int _kCommaPausePercent = 45;
const int _kDashPausePercent = 60;
const int _kClausePausePercent = 80;
const int _kEllipsisPausePercent = 110;
const int _kSentencePausePercent = 135;
const int _kStrongSentencePausePercent = 150;

// ---------------------------------------------------------------------------
// Known abbreviations (22 entries, case-insensitive)
// ---------------------------------------------------------------------------

const Set<String> _kKnownAbbreviations = {
  'mr.',
  'mrs.',
  'ms.',
  'dr.',
  'prof.',
  'sr.',
  'jr.',
  'st.',
  'vs.',
  'etc.',
  'e.g.',
  'i.e.',
  'cf.',
  'no.',
  'fig.',
  'eq.',
  'inc.',
  'ltd.',
  'co.',
  'dept.',
  'mt.',
  'ft.',
};

// ---------------------------------------------------------------------------
// Character classification
// ---------------------------------------------------------------------------

/// Extended Latin lowercase code points (beyond Latin-1).
const Set<int> _kExtendedLowercaseSet = {
  0x101,
  0x103,
  0x105,
  0x107,
  0x10D,
  0x10F,
  0x111,
  0x113,
  0x117,
  0x119,
  0x11B,
  0x11F,
  0x12B,
  0x12F,
  0x131,
  0x137,
  0x13C,
  0x142,
  0x144,
  0x146,
  0x151,
  0x153,
  0x159,
  0x15B,
  0x15F,
  0x161,
  0x167,
  0x16B,
  0x16F,
  0x171,
  0x173,
  0x17A,
  0x17C,
  0x17E,
};

/// Extended Latin uppercase code points (beyond Latin-1).
const Set<int> _kExtendedUppercaseSet = {
  0x100,
  0x102,
  0x104,
  0x106,
  0x10C,
  0x10E,
  0x110,
  0x112,
  0x116,
  0x118,
  0x11A,
  0x11E,
  0x12A,
  0x12E,
  0x130,
  0x136,
  0x13B,
  0x141,
  0x143,
  0x145,
  0x150,
  0x152,
  0x158,
  0x15A,
  0x15E,
  0x160,
  0x166,
  0x16A,
  0x16E,
  0x170,
  0x172,
  0x179,
  0x17B,
  0x17D,
};

/// Extended Latin vowels (lowercase code points).
const Set<int> _kExtendedVowelSet = {
  0x101, 0x103, 0x105, // ā ă ą
  0x113, 0x117, 0x119, 0x11B, // ē ė ę ě
  0x12B, 0x12F, 0x131, // ī į ı
  0x151, 0x153, // ő œ
  0x16B, 0x16F, 0x171, 0x173, // ū ů ű ų
};

/// Map from extended Latin uppercase to lowercase.
const Map<int, int> _kExtendedToLowerMap = {
  0x100: 0x101,
  0x102: 0x103,
  0x104: 0x105,
  0x106: 0x107,
  0x10C: 0x10D,
  0x10E: 0x10F,
  0x110: 0x111,
  0x112: 0x113,
  0x116: 0x117,
  0x118: 0x119,
  0x11A: 0x11B,
  0x11E: 0x11F,
  0x12A: 0x12B,
  0x12E: 0x12F,
  0x130: 0x131,
  0x136: 0x137,
  0x13B: 0x13C,
  0x141: 0x142,
  0x143: 0x144,
  0x145: 0x146,
  0x150: 0x151,
  0x152: 0x153,
  0x158: 0x159,
  0x15A: 0x15B,
  0x15E: 0x15F,
  0x160: 0x161,
  0x166: 0x167,
  0x16A: 0x16B,
  0x16E: 0x16F,
  0x170: 0x171,
  0x172: 0x173,
  0x179: 0x17A,
  0x17B: 0x17C,
  0x17D: 0x17E,
};

bool _isDigit(int c) => c >= 0x30 && c <= 0x39;

bool _isUppercaseLetter(int c) {
  if (c >= 0x41 && c <= 0x5A) return true; // A-Z
  if (c >= 0xC0 && c <= 0xD6) return true; // Latin-1 upper block 1
  if (c >= 0xD8 && c <= 0xDE) return true; // Latin-1 upper block 2
  return _kExtendedUppercaseSet.contains(c);
}

bool _isLowercaseLetter(int c) {
  if (c >= 0x61 && c <= 0x7A) return true; // a-z
  if (c == 0xDF) return true; // ß
  if (c >= 0xE0 && c <= 0xF6) return true; // Latin-1 lower block 1
  if (c >= 0xF8 && c <= 0xFF) return true; // Latin-1 lower block 2
  return _kExtendedLowercaseSet.contains(c);
}

bool _isLetter(int c) => _isUppercaseLetter(c) || _isLowercaseLetter(c);

bool _isWordCharacter(int c) => _isLetter(c) || _isDigit(c);

bool _isVowel(int c) {
  // ASCII vowels (lowercase)
  if (c == 0x61 ||
      c == 0x65 ||
      c == 0x69 ||
      c == 0x6F ||
      c == 0x75 ||
      c == 0x79) {
    return true; // a e i o u y
  }
  // Latin-1 accented vowels
  if (c >= 0xE0 && c <= 0xE6) return true; // à á â ã ä å æ
  if (c >= 0xE8 && c <= 0xEB) return true; // è é ê ë
  if (c >= 0xEC && c <= 0xEF) return true; // ì í î ï
  if (c >= 0xF2 && c <= 0xF6) return true; // ò ó ô õ ö
  if (c == 0xF8) return true; // ø
  if (c >= 0xF9 && c <= 0xFC) return true; // ù ú û ü
  if (c == 0xFD || c == 0xFF) return true; // ý ÿ
  // Extended Latin vowels
  return _kExtendedVowelSet.contains(c);
}

int _toLowercase(int c) {
  if (c >= 0x41 && c <= 0x5A) return c + 32; // A-Z
  if (c >= 0xC0 && c <= 0xD6) return c + 32; // Latin-1 upper block 1
  if (c >= 0xD8 && c <= 0xDE) return c + 32; // Latin-1 upper block 2
  return _kExtendedToLowerMap[c] ?? c;
}

bool _isSegmentSeparator(int c) => c == 0x2D || c == 0x2F || c == 0x5F; // - / _

bool _isTechnicalConnector(int c) =>
    c == 0x2D ||
    c == 0x2F ||
    c == 0x5F || // - / _
    c == 0x2E ||
    c == 0x2B ||
    c == 0x5C; // . + \

bool _isIgnoredTrailingChar(int c) =>
    c == 0x22 ||
    c == 0x27 ||
    c == 0x29 || // " ' )
    c == 0x5D ||
    c == 0x7D; // ] }

// ---------------------------------------------------------------------------
// Counting helpers
// ---------------------------------------------------------------------------

/// Counts readable (word) characters in [w].
int readableCharacterCount(String w) {
  var count = 0;
  for (var i = 0; i < w.length; i++) {
    if (_isWordCharacter(w.codeUnitAt(i))) count++;
  }
  return count;
}

int _letterCount(String w) {
  var count = 0;
  for (var i = 0; i < w.length; i++) {
    if (_isLetter(w.codeUnitAt(i))) count++;
  }
  return count;
}

int _digitCount(String w) {
  var count = 0;
  for (var i = 0; i < w.length; i++) {
    if (_isDigit(w.codeUnitAt(i))) count++;
  }
  return count;
}

int _uppercaseLetterCount(String w) {
  var count = 0;
  for (var i = 0; i < w.length; i++) {
    if (_isUppercaseLetter(w.codeUnitAt(i))) count++;
  }
  return count;
}

// ---------------------------------------------------------------------------
// Structural analysis
// ---------------------------------------------------------------------------

/// Counts approximate syllable groups via vowel-group detection.
int approximateSyllableGroups(String w) {
  var groups = 0;
  var letterCount = 0;
  var previousWasVowel = false;
  final lettersOnly = StringBuffer();

  for (var i = 0; i < w.length; i++) {
    final c = w.codeUnitAt(i);
    if (!_isLetter(c)) {
      previousWasVowel = false;
      continue;
    }

    letterCount++;
    final lowered = _toLowercase(c);
    lettersOnly.writeCharCode(lowered);

    final vowel = _isVowel(lowered);
    if (vowel && !previousWasVowel) {
      groups++;
    }
    previousWasVowel = vowel;
  }

  // Silent-e adjustment
  final letters = lettersOnly.toString();
  if (groups > 1 &&
      letterCount > 3 &&
      letters.endsWith('e') &&
      !letters.endsWith('le') &&
      !letters.endsWith('ye')) {
    groups--;
  }

  if (groups == 0 && letterCount > 0) {
    groups = 1;
  }

  return groups;
}

int _compoundJoinerCount(String w) {
  var count = 0;
  for (var i = 1; i + 1 < w.length; i++) {
    if (!_isSegmentSeparator(w.codeUnitAt(i))) continue;
    if (!_isWordCharacter(w.codeUnitAt(i - 1))) continue;
    if (!_isWordCharacter(w.codeUnitAt(i + 1))) continue;
    count++;
  }
  return count;
}

int _technicalConnectorCount(String w) {
  var count = 0;
  for (var i = 1; i + 1 < w.length; i++) {
    if (!_isTechnicalConnector(w.codeUnitAt(i))) continue;
    if (!_isWordCharacter(w.codeUnitAt(i - 1))) continue;
    if (!_isWordCharacter(w.codeUnitAt(i + 1))) continue;
    count++;
  }
  return count;
}

int _lastMeaningfulCharIndex(String w) {
  for (var i = w.length - 1; i >= 0; i--) {
    if (!_isIgnoredTrailingChar(w.codeUnitAt(i))) return i;
  }
  return -1;
}

int _trailingRhythmCharCode(String w) {
  final index = _lastMeaningfulCharIndex(w);
  if (index >= 0) return w.codeUnitAt(index);
  return 0;
}

int _trailingRepeatedCharCount(String w, int target) {
  var count = 0;
  for (var i = _lastMeaningfulCharIndex(w); i >= 0; i--) {
    if (w.codeUnitAt(i) != target) break;
    count++;
  }
  return count;
}

bool _endsWithEllipsis(String w) =>
    _trailingRepeatedCharCount(w, 0x2E) >= 3; // '.'

/// Whether [w] starts with a lowercase letter.
bool startsWithLowercaseLetter(String? w) {
  if (w == null || w.isEmpty) return false;
  for (var i = 0; i < w.length; i++) {
    final c = w.codeUnitAt(i);
    if (_isLowercaseLetter(c)) return true;
    if (_isLetter(c)) return false; // uppercase letter → false
  }
  return false;
}

bool _isDottedInitialism(String w) {
  final end = _lastMeaningfulCharIndex(w);
  if (end <= 0) return false;

  var letterCount = 0;
  var expectLetter = true;
  for (var i = 0; i <= end; i++) {
    final c = w.codeUnitAt(i);
    if (expectLetter) {
      if (!_isLetter(c)) return false;
      letterCount++;
      expectLetter = false;
    } else if (c == 0x2E) {
      // '.'
      expectLetter = true;
    } else {
      return false;
    }
  }

  return expectLetter && letterCount >= 2;
}

bool _looksLikeAbbreviation(String w, bool nextStartsLowercase) {
  // Lowercase the word for known-list comparison
  final lowered = _lowercaseString(w);

  // Check known abbreviation list
  if (_kKnownAbbreviations.contains(lowered)) return true;

  // Must end with '.' to continue checks
  if (!lowered.endsWith('.')) return false;

  // Dotted initialism (e.g. U.S.)
  if (_isDottedInitialism(w)) return true;

  final readable = readableCharacterCount(w);

  // Very short words always treated as abbreviations
  if (readable <= 2) return true;

  // Short word + next starts lowercase → abbreviation
  if (nextStartsLowercase && readable <= 4) return true;

  return false;
}

String _lowercaseString(String w) {
  final buf = StringBuffer();
  for (var i = 0; i < w.length; i++) {
    buf.writeCharCode(_toLowercase(w.codeUnitAt(i)));
  }
  return buf.toString();
}

// ---------------------------------------------------------------------------
// Bonus calculations
// ---------------------------------------------------------------------------

int _lengthBonusPercent(String w) {
  final readable = readableCharacterCount(w);
  if (readable == 0) return 0;

  var bonusPercent = 0;

  if (readable > _kLongWordAfterChars) {
    final extra = readable - _kLongWordAfterChars;
    bonusPercent += extra * _kLongWordPercentPerChar;
  }
  if (readable > _kVeryLongWordAfterChars) {
    final extra = readable - _kVeryLongWordAfterChars;
    bonusPercent += extra * _kVeryLongWordPercentPerChar;
  }
  if (readable > _kUltraLongWordAfterChars) {
    final extra = readable - _kUltraLongWordAfterChars;
    bonusPercent += extra * _kUltraLongWordPercentPerChar;
  }

  final joinerCount = _compoundJoinerCount(w);
  if (joinerCount > 0) {
    bonusPercent += joinerCount * _kCompoundJoinerPercent;
    if (readable >= _kVeryLongWordAfterChars) {
      bonusPercent += _kLongCompoundWordPercent;
    }
  }

  final techCount = _technicalConnectorCount(w);
  if (techCount > joinerCount) {
    bonusPercent += (techCount - joinerCount) * _kTechnicalConnectorPercent;
  }

  return bonusPercent < _kLongWordMaxPercent
      ? bonusPercent
      : _kLongWordMaxPercent;
}

int _complexityBonusPercent(String w) {
  var bonusPercent = 0;

  final syllableGroups = approximateSyllableGroups(w);
  if (syllableGroups > _kSyllableBonusAfterCount) {
    final extraGroups = syllableGroups - _kSyllableBonusAfterCount;
    final syllableBonus = extraGroups * _kSyllableBonusPercentPerGroup;
    bonusPercent += syllableBonus < _kSyllableBonusMaxPercent
        ? syllableBonus
        : _kSyllableBonusMaxPercent;
  }

  final letters = _letterCount(w);
  final digits = _digitCount(w);
  final uppercase = _uppercaseLetterCount(w);

  if (letters > 0 && digits > 0) {
    bonusPercent += _kMixedTokenComplexityPercent;
  } else if (digits >= 3) {
    bonusPercent += _kNumericTokenComplexityPercent;
  }

  if (uppercase >= 2 && uppercase == letters) {
    bonusPercent += _kAllCapsComplexityPercent;
  }

  final techCount = _technicalConnectorCount(w);
  if (techCount >= 2) {
    bonusPercent += (techCount - 1) * _kDenseConnectorComplexityPercent;
  }

  return bonusPercent < _kComplexWordMaxPercent
      ? bonusPercent
      : _kComplexWordMaxPercent;
}

int _punctuationPausePercent(String w, bool nextStartsLowercase) {
  if (_endsWithEllipsis(w)) return _kEllipsisPausePercent;

  final rhythm = _trailingRhythmCharCode(w);
  switch (rhythm) {
    case 0x2C: // ','
      return _kCommaPausePercent;
    case 0x2D: // '-'
      return _kDashPausePercent;
    case 0x3B: // ';'
    case 0x3A: // ':'
      return _kClausePausePercent;
    case 0x2E: // '.'
      if (!_looksLikeAbbreviation(w, nextStartsLowercase)) {
        return _kSentencePausePercent;
      }
      return 0;
    case 0x21: // '!'
    case 0x3F: // '?'
      return _kStrongSentencePausePercent;
    default:
      return 0;
  }
}

// ---------------------------------------------------------------------------
// Scaling
// ---------------------------------------------------------------------------

int _scaledPercent(int basePercent, int scalePercent) {
  final clamped = scalePercent < 25 ? 25 : scalePercent;
  return (basePercent * clamped) ~/ 100;
}

int _scaledDelayMs(int bonusPercent, int delayMs) {
  final clamped = delayMs > 600 ? 600 : (delayMs < 0 ? 0 : delayMs);
  return (bonusPercent * clamped) ~/ 100;
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Returns total display duration in ms for [word], given [nextWord]
/// for abbreviation context and the base interval (60000 / wpm).
///
/// Pure, deterministic, no side effects.
int durationForWord(
  String word, {
  required String? nextWord,
  required int baseIntervalMs,
  required PacingConfig config,
}) {
  if (word.isEmpty || baseIntervalMs == 0) return baseIntervalMs;

  final nextStartsLower = startsWithLowercaseLetter(nextWord);

  final lengthBonus = _lengthBonusPercent(word);
  final complexityBonus = _complexityBonusPercent(word);
  final punctuationPause = _punctuationPausePercent(word, nextStartsLower);

  var totalBonusMs = 0;
  totalBonusMs += _scaledDelayMs(
    _scaledPercent(lengthBonus, config.longWordScalePercent),
    config.longWordDelayMs,
  );
  totalBonusMs += _scaledDelayMs(
    _scaledPercent(complexityBonus, config.complexWordScalePercent),
    config.complexWordDelayMs,
  );
  totalBonusMs += _scaledDelayMs(
    _scaledPercent(punctuationPause, config.punctuationScalePercent),
    config.punctuationDelayMs,
  );

  return baseIntervalMs + totalBonusMs;
}
