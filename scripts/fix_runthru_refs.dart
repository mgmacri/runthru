// ignore_for_file: avoid_print
import 'dart:io';

/// Replaces direct "RunThru" references in the backlog with
/// "legacy app name" phrasing, while preserving grep patterns that
/// need the literal string to function.
void main() {
  final file = File('doc/runthru-backlog.json');
  var content = file.readAsStringSync();

  // Descriptions and titles
  content = content.replaceAll(
    'remove all RunThru references',
    'remove all legacy app name references',
  );
  content = content.replaceAll(
    'Remove all RunThru references from Dart source',
    'Remove all legacy app name references from Dart source',
  );
  content = content.replaceAll(
    'Remove all RunThru references from platform configs',
    'Remove all legacy app name references from platform configs',
  );

  // Acceptance criteria
  content = content.replaceAll(
    "Zero occurrences of 'RunThru', 'runthru', or 'RunThru' in lib/**/*.dart (excluding .g.dart)",
    "Zero occurrences of legacy app name variants in lib/**/*.dart (excluding .g.dart) — grep pattern: 'speedy.boy'",
  );
  content = content.replaceAll(
    "Zero occurrences of 'RunThru', 'runthru', or 'RunThru' in test/**/*.dart",
    "Zero occurrences of legacy app name variants in test/**/*.dart — grep pattern: 'speedy.boy'",
  );
  content = content.replaceAll(
    "pubspec.yaml description references RunThru, not RunThru",
    "pubspec.yaml description references RunThru, not the legacy app name",
  );
  content = content.replaceAll(
    "No 'speedy' or 'RunThru' references in android/ directory",
    "Zero matches for legacy app name pattern in android/ directory — grep pattern: 'speedy'",
  );
  content = content.replaceAll(
    "No 'speedy' or 'RunThru' references in ios/ directory",
    "Zero matches for legacy app name pattern in ios/ directory — grep pattern: 'speedy'",
  );
  content = content.replaceAll(
    "Icons do not reference 'RunThru' visually or in filenames",
    "Icons do not reference the legacy app name visually or in filenames",
  );

  // Granularity rationale
  content = content.replaceAll(
    'no RunThru references',
    'no legacy app name references',
  );

  file.writeAsStringSync(content);

  // Verify
  final remaining = RegExp(
    r'Speedy\s*Boy',
    caseSensitive: false,
  ).allMatches(content).length;
  print('RunThru references remaining: $remaining');

  // grep patterns use 'speedy.boy' and 'speedy' which are functional patterns, not brand references
  final grepPatterns = RegExp(r"'speedy").allMatches(content).length;
  print('Functional grep patterns (expected): $grepPatterns');
}
