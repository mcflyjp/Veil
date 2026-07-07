import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/client_manager.dart';
import 'core/router.dart';
import 'core/aim_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final clientManager = ClientManager();
  await clientManager.init();
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
