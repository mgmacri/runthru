import 'package:flutter/widgets.dart';

/// Returns true if the user has requested reduced motion.
bool isReducedMotion(BuildContext context) {
  final data = MediaQuery.of(context);
  return data.accessibleNavigation || data.disableAnimations;
}
