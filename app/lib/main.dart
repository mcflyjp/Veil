import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'core/client_manager.dart';
import 'core/notification_service.dart';
import 'core/router.dart';
import 'core/aim_theme.dart';
import 'core/veil_theme.dart';
import 'core/veil_user_prefs.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.instance.init();
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

  // Attach the Matrix client whenever the user is logged in so settings
  // are synced to/from Matrix account data automatically.
  clientManager.addListener(() {
    if (clientManager!.isLoggedIn) {
      prefs.attachClient(clientManager.client);
    } else {
      prefs.detachClient();
    }
  });
  // Attach immediately if already logged in (e.g. app restart with saved session).
  if (clientManager.isLoggedIn) {
    prefs.attachClient(clientManager.client);
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: clientManager),
        ChangeNotifierProvider.value(value: prefs),
      ],
      child: VeilApp(clientManager: clientManager),
    ),
  );
}

class VeilApp extends StatefulWidget {
  final ClientManager clientManager;
  const VeilApp({super.key, required this.clientManager});
  @override
  State<VeilApp> createState() => _VeilAppState();
}

class _VeilAppState extends State<VeilApp> {
  late final _router = buildRouter(widget.clientManager);

  @override
  void initState() {
    super.initState();
    NotificationService.instance.onTap = (roomId) {
      _router.go('/buddylist/chat/${Uri.encodeComponent(roomId)}');
    };
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
