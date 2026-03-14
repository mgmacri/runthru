import 'package:flutter/material.dart';
import 'package:speedy_boy/design/design.dart';
import 'package:speedy_boy/navigation/app_router.dart';

/// Speedy Boy MaterialApp with ThemeExtension and go_router.
class SpeedyBoyApp extends StatelessWidget {
  const SpeedyBoyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Speedy Boy',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: SpeedyBoyTokens.shellBase,
        extensions: const [SpeedyBoyTokens.instance],
      ),
      routerConfig: appRouter,
    );
  }
}
