import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'client_manager.dart';
import '../screens/login_screen.dart';
import '../screens/chat_screen.dart';
import '../screens/new_chat_screen.dart';
import '../screens/settings_screen.dart';
import '../widgets/split_shell.dart';

/// Instant page swap — no slide/fade animation so there is no gray flash.
Page<void> _noTransition(Widget child) =>
    NoTransitionPage<void>(child: child);

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

        ShellRoute(
          builder: (context, state, child) =>
              SplitShell(child: child, matchedLocation: state.matchedLocation),
          routes: [
            GoRoute(
              path: '/buddylist',
              pageBuilder: (_, __) => _noTransition(const SelectConversationPanel()),
              routes: [
                GoRoute(
                  path: 'chat/:roomId',
                  pageBuilder: (_, state) => _noTransition(
                    ChatScreen(roomId: state.pathParameters['roomId']!),
                  ),
                ),
                GoRoute(
                  path: 'new',
                  pageBuilder: (_, __) => _noTransition(const NewChatScreen()),
                ),
                GoRoute(
                  path: 'settings',
                  pageBuilder: (_, __) => _noTransition(const SettingsScreen()),
                ),
              ],
            ),
          ],
        ),
      ],
    );
