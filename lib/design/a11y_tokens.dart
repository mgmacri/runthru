/// Accessibility sizing tokens — minimum interactive target sizes.
///
/// WCAG 2.2 / platform guidance: interactive elements must be at least
/// 48×48 dp on Android and 44×44 dp on iOS. RunThru uses the stricter
/// Android value everywhere so a single constant satisfies both.
abstract final class RunThruA11y {
  /// Minimum tap-target edge in dp (Android material guideline).
  static const double minTapTarget = 48.0;
}
