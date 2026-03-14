import 'package:go_router/go_router.dart';
import 'package:speedy_boy/navigation/cube_transition.dart';
import 'package:speedy_boy/screens/library_screen.dart';
import 'package:speedy_boy/screens/reading_screen.dart';
import 'package:speedy_boy/screens/settings_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      pageBuilder: (context, state) => cubeTransitionPage(
        key: state.pageKey,
        child: const LibraryScreen(),
      ),
    ),
    GoRoute(
      path: '/read',
      pageBuilder: (context, state) {
        final filePath = state.uri.queryParameters['path'] ?? '';
        return cubeTransitionPage(
          key: state.pageKey,
          direction: -1,
          child: ReadingScreen(filePath: filePath),
        );
      },
    ),
    GoRoute(
      path: '/settings',
      pageBuilder: (context, state) => cubeTransitionPage(
        key: state.pageKey,
        child: const SettingsScreen(),
      ),
    ),
  ],
);
