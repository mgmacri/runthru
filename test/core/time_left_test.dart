import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/core/time_left.dart';

void main() {
  test('formats minutes and hours', () {
    expect(formatTimeLeft(0), '< 1 min left');
    expect(formatTimeLeft(1), '< 1 min left');
    expect(formatTimeLeft(12), '12 min left');
    expect(formatTimeLeft(59), '59 min left');
    expect(formatTimeLeft(120), '2 h left');
    expect(formatTimeLeft(461), '7 h 41 min left');
  });
}
