import 'dart:convert';
import 'dart:io';

void main() {
  final j = jsonDecode(File('doc/runthru-backlog.json').readAsStringSync())
      as Map<String, dynamic>;
  print('Valid JSON: ${j['project']}');
  print('Releases: ${(j['releases'] as List).length}');

  var nodeCount = 0;
  void countNodes(dynamic n) {
    if (n is Map) {
      if (n.containsKey('id')) nodeCount++;
      for (final v in n.values) {
        countNodes(v);
      }
    } else if (n is List) {
      for (final item in n) {
        countNodes(item);
      }
    }
  }
  countNodes(j);
  print('Total nodes with id: $nodeCount');

  var missing = 0;
  void checkRationale(dynamic n) {
    if (n is Map) {
      if (n.containsKey('id') && !n.containsKey('granularity_rationale')) {
        missing++;
        print('  MISSING rationale: ${n['id']}');
      }
      for (final v in n.values) {
        checkRationale(v);
      }
    } else if (n is List) {
      for (final item in n) {
        checkRationale(item);
      }
    }
  }
  checkRationale(j);
  print('Missing granularity_rationale: $missing');

  var psCount = 0;
  void checkPowerShell(dynamic n) {
    if (n is Map) {
      if (n.containsKey('verification_command')) {
        final c = n['verification_command'] as String;
        if (c.contains('Test-Path') ||
            c.contains('Select-String') ||
            c.contains('findstr')) {
          psCount++;
          print('  PS cmd: $c');
        }
      }
      for (final v in n.values) {
        checkPowerShell(v);
      }
    } else if (n is List) {
      for (final item in n) {
        checkPowerShell(item);
      }
    }
  }
  checkPowerShell(j);
  print('PowerShell commands remaining: $psCount');

  // Check ethical_blockers
  final blockerNodes = <String>[];
  void checkBlockers(dynamic n) {
    if (n is Map) {
      if (n.containsKey('ethical_blockers')) {
        blockerNodes.add(n['id'] as String);
      }
      for (final v in n.values) {
        checkBlockers(v);
      }
    } else if (n is List) {
      for (final item in n) {
        checkBlockers(item);
      }
    }
  }
  checkBlockers(j);
  print('Nodes with ethical_blockers: ${blockerNodes.join(', ')}');

  // Check R3 weeks
  for (final r in j['releases'] as List) {
    final release = r as Map<String, dynamic>;
    if (release['id'] == 'R3') {
      print('R3 weeks: ${release['weeks']}');
    }
  }

  // Check E1.3.2 depends_on
  void findE132(dynamic n) {
    if (n is Map) {
      if (n['id'] == 'E1.3.2') {
        print('E1.3.2 depends_on: ${n['depends_on']}');
      }
      for (final v in n.values) {
        findE132(v);
      }
    } else if (n is List) {
      for (final item in n) {
        findE132(item);
      }
    }
  }
  findE132(j);

  // Check no Speedy Boy references
  final content = File('doc/runthru-backlog.json').readAsStringSync();
  final speedyCount =
      RegExp(r'[Ss]peedy\s*[Bb]oy', caseSensitive: false).allMatches(content).length;
  print('Speedy Boy references: $speedyCount');

  print('\n=== VALIDATION ${missing == 0 && psCount == 0 && speedyCount == 0 ? "PASSED" : "FAILED"} ===');
}
