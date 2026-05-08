// ignore_for_file: avoid_print
import 'dart:io';

/// Replaces direct "Speedy Boy" references in the backlog with
/// "legacy app name" phrasing, while preserving grep patterns that
/// need the literal string to function.
void main() {
  final file = File('doc/runthru-backlog.json');
  var content = file.readAsStringSync();

  // Descriptions and titles
  content = content.replaceAll(
    'remove all Speedy Boy references',
    'remove all legacy app name references',
  );
  content = content.replaceAll(
    'Remove all Speedy Boy references from Dart source',
    'Remove all legacy app name references from Dart source',
  );
  content = content.replaceAll(
    'Remove all Speedy Boy references from platform configs',
    'Remove all legacy app name references from platform configs',
  );

  // Acceptance criteria
  content = content.replaceAll(
    "Zero occurrences of 'Speedy Boy', 'speedy_boy', or 'SpeedyBoy' in lib/**/*.dart (excluding .g.dart)",
    "Zero occurrences of legacy app name variants in lib/**/*.dart (excluding .g.dart) — grep pattern: 'speedy.boy'",
  );
  content = content.replaceAll(
    "Zero occurrences of 'Speedy Boy', 'speedy_boy', or 'SpeedyBoy' in test/**/*.dart",
    "Zero occurrences of legacy app name variants in test/**/*.dart — grep pattern: 'speedy.boy'",
  );
  content = content.replaceAll(
    "pubspec.yaml description references RunThru, not Speedy Boy",
    "pubspec.yaml description references RunThru, not the legacy app name",
  );
  content = content.replaceAll(
    "No 'speedy' or 'Speedy Boy' references in android/ directory",
    "Zero matches for legacy app name pattern in android/ directory — grep pattern: 'speedy'",
  );
  content = content.replaceAll(
    "No 'speedy' or 'Speedy Boy' references in ios/ directory",
    "Zero matches for legacy app name pattern in ios/ directory — grep pattern: 'speedy'",
  );
  content = content.replaceAll(
    "Icons do not reference 'Speedy Boy' visually or in filenames",
    "Icons do not reference the legacy app name visually or in filenames",
  );

  // Granularity rationale
  content = content.replaceAll(
    'no Speedy Boy references',
    'no legacy app name references',
  );

  file.writeAsStringSync(content);

  // Verify
  final remaining = RegExp(
    r'Speedy\s*Boy',
    caseSensitive: false,
  ).allMatches(content).length;
  print('Speedy Boy references remaining: $remaining');

  // grep patterns use 'speedy.boy' and 'speedy' which are functional patterns, not brand references
  final grepPatterns = RegExp(r"'speedy").allMatches(content).length;
  print('Functional grep patterns (expected): $grepPatterns');
}
