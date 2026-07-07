import 'package:go_router/go_router.dart';
import 'client_manager.dart';
import '../screens/login_screen.dart';
import '../screens/buddy_list_screen.dart';
import '../screens/chat_screen.dart';
import '../screens/new_chat_screen.dart';
import '../screens/settings_screen.dart';

GoRouter buildRouter(ClientManager mgr) => GoRouter(
      initialLocation: '/buddylist',
      refreshListenable: mgr,
      redirect: (context, state) {
        if (!mgr.isReady) return null;
        final loggedIn = mgr.isLoggedIn;
        final onAuth = state.matchedLocation.startsWith('/login');
        if (!loggedIn && !onAuth) return '/login';
        if (loggedIn && onAuth) return '/buddylist';
        return null;
      },
      routes: [
        GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
        GoRoute(
          path: '/buddylist',
          builder: (_, __) => const BuddyListScreen(),
          routes: [
            GoRoute(
              path: 'chat/:roomId',
              builder: (_, state) => ChatScreen(roomId: state.pathParameters['roomId']!),
            ),
            GoRoute(path: 'new', builder: (_, __) => const NewChatScreen()),
            GoRoute(path: 'settings', builder: (_, __) => const SettingsScreen()),
          ],
        ),
      ],
    );

// Kept for import compatibility — unused after refactor
final appRouter = GoRouter(initialLocation: '/login', routes: [
  GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
]);
