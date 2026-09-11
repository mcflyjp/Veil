import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'core/call_service.dart';
import 'core/client_manager.dart';
import 'core/notification_service.dart';
import 'core/push_service.dart';
import 'core/router.dart';
import 'core/aim_theme.dart';
import 'core/veil_theme.dart';
import 'core/veil_user_prefs.dart';

// App entry point. Boots NotificationService and the Matrix ClientManager
// before the first frame, wires both plus VeilUserPrefs into a MultiProvider,
// and builds the root MaterialApp.router widget (VeilApp below) that hosts
// the go_router route table from core/router.dart.

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.instance.init();
  await PushService.instance.init();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
  ));

  ClientManager? clientManager;
  Object? startupError;

  try {
    clientManager = ClientManager();
    await clientManager.init();
  } catch (e) {
    startupError = e;
  }

  if (startupError != null || clientManager == null) {
    runApp(MaterialApp(
      home: Scaffold(
        backgroundColor: const Color(0xFF003580),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Startup error:\n$startupError',
              style: const TextStyle(color: Colors.white, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    ));
    return;
  }

  final prefs = VeilUserPrefs();
  final calls = CallService();

  // Attach the Matrix client whenever the user is logged in so settings are
  // synced to/from Matrix account data automatically, CallService can
  // send/receive m.call.* signaling, and PushService can register this
  // device's FCM token as a pusher for that account.
  clientManager.addListener(() {
    if (clientManager!.isLoggedIn) {
      prefs.attachClient(clientManager.client);
      calls.attachClient(clientManager.client);
      PushService.instance.attachClient(clientManager.client);
    } else {
      prefs.detachClient();
      calls.detachClient();
      PushService.instance.detachClient();
    }
  });
  // Attach immediately if already logged in (e.g. app restart with saved session).
  if (clientManager.isLoggedIn) {
    prefs.attachClient(clientManager.client);
    calls.attachClient(clientManager.client);
    PushService.instance.attachClient(clientManager.client);
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: clientManager),
        ChangeNotifierProvider.value(value: prefs),
        ChangeNotifierProvider.value(value: calls),
      ],
      child: VeilApp(clientManager: clientManager),
    ),
  );
}

// ── Root widget ──────────────────────────────────────────────────────────
// Picks light/dark Material baseline based on the active Veil theme and
// hands off routing to the GoRouter built in initState.

class VeilApp extends StatefulWidget {
  final ClientManager clientManager;
  const VeilApp({super.key, required this.clientManager});
  @override
  State<VeilApp> createState() => _VeilAppState();
}

class _VeilAppState extends State<VeilApp> {
  late final _router = buildRouter(widget.clientManager);
  StreamSubscription? _incomingCallSub;

  @override
  void initState() {
    super.initState();
    NotificationService.instance.onTap = (roomId) {
      _router.go('/buddylist/chat/${Uri.encodeComponent(roomId)}');
    };
    // The app process itself may have just been started by tapping a
    // notification (fully closed -> tap -> cold launch) rather than a
    // notification arriving while already running — that case goes through
    // onTap above via onDidReceiveNotificationResponse instead, and doesn't
    // set pendingLaunchRoomId. Consume it once, after a frame so the router
    // has a route to redirect from (redirect logic depends on auth state
    // being ready, which isn't guaranteed on the very first frame).
    final pendingRoomId = NotificationService.instance.pendingLaunchRoomId;
    if (pendingRoomId != null) {
      NotificationService.instance.pendingLaunchRoomId = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _router.go('/buddylist/chat/${Uri.encodeComponent(pendingRoomId)}');
      });
    }
    // Pushes the incoming-call screen over whatever's currently on screen.
    // CallService (registered on the MultiProvider above VeilApp) is safe
    // to read here since it's already mounted as an ancestor.
    _incomingCallSub = context.read<CallService>().onIncomingCall.listen((_) {
      _router.push('/call/incoming');
    });
  }

  @override
  void dispose() {
    _incomingCallSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<VeilUserPrefs>();
    final tc = prefs.colors;
    // dark/glass Veil themes use dark Material baseline; aim/light use light
    final isDark = prefs.theme == VeilThemeMode.dark || prefs.theme == VeilThemeMode.glass;
    return MaterialApp.router(
      title: 'Veil',
      // Override scaffold background so Navigator transitions don't flash the
      // wrong color (e.g. AIM gray on glass/dark themes).
      theme: AimTheme.light.copyWith(scaffoldBackgroundColor: tc.scaffold),
      darkTheme: AimTheme.dark.copyWith(scaffoldBackgroundColor: tc.scaffold),
      themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
      routerConfig: _router,
      debugShowCheckedModeBanner: false,
    );
  }
}
