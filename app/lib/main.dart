import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/client_manager.dart';
import 'core/router.dart';
import 'core/aim_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: clientManager),
        ChangeNotifierProvider(create: (_) => ThemeModeNotifier()),
      ],
      child: VeilApp(clientManager: clientManager),
    ),
  );
}

class VeilApp extends StatelessWidget {
  final ClientManager clientManager;
  const VeilApp({super.key, required this.clientManager});

  @override
  Widget build(BuildContext context) {
    final themeNotifier = context.watch<ThemeModeNotifier>();
    return MaterialApp.router(
      title: 'Veil',
      theme: AimTheme.light,
      darkTheme: AimTheme.dark,
      themeMode: themeNotifier.mode,
      routerConfig: buildRouter(clientManager),
      debugShowCheckedModeBanner: false,
    );
  }
}

class ThemeModeNotifier extends ChangeNotifier {
  ThemeMode _mode = ThemeMode.system;
  ThemeMode get mode => _mode;

  void toggle() {
    _mode = _mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
  }
}
