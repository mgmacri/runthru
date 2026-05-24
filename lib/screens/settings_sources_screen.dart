import 'package:flutter/material.dart';
import 'package:runthru/screens/sources_screen.dart';

/// Compatibility route for the previous Settings > Sources entry point.
class SettingsSourcesScreen extends StatelessWidget {
  /// Creates the pushed Sources screen with a back button.
  const SettingsSourcesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const SourcesScreen(showBackButton: true);
  }
}
