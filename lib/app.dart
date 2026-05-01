import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runthru/design/design.dart';
import 'package:runthru/navigation/app_router.dart';

/// RunThru MaterialApp with ThemeExtension and go_router.
class RunThruApp extends ConsumerWidget {
  const RunThruApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'RunThru',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: RunThruTokens.shellBase,
        extensions: const [RunThruTokens.instance],
      ),
      routerConfig: appRouter,
    );
  }
}
