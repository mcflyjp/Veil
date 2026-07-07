import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../core/client_manager.dart';
import '../core/aim_theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _displayNameCtrl = TextEditingController();
  bool _isRegistering = false;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _displayNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() { _loading = true; _error = null; });
    final mgr = context.read<ClientManager>();
    try {
      if (_isRegistering) {
        await mgr.register(_usernameCtrl.text.trim(), _passwordCtrl.text, _displayNameCtrl.text.trim());
      } else {
        await mgr.login(_usernameCtrl.text.trim(), _passwordCtrl.text);
      }
      if (mounted) context.go('/buddylist');
    } catch (e) {
      setState(() { _error = e.toString().replaceAll('Exception: ', ''); });
    } finally {
      if (mounted) setState(() { _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _AimLoginWindow(
                  isRegistering: _isRegistering,
                  usernameCtrl: _usernameCtrl,
                  passwordCtrl: _passwordCtrl,
                  displayNameCtrl: _displayNameCtrl,
                  loading: _loading,
                  error: _error,
                  isDark: isDark,
                  onSubmit: _submit,
                  onToggle: () => setState(() { _isRegistering = !_isRegistering; _error = null; }),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AimLoginWindow extends StatelessWidget {
  final bool isRegistering;
  final TextEditingController usernameCtrl;
  final TextEditingController passwordCtrl;
  final TextEditingController displayNameCtrl;
  final bool loading;
  final String? error;
  final bool isDark;
  final VoidCallback onSubmit;
  final VoidCallback onToggle;

  const _AimLoginWindow({
    required this.isRegistering,
    required this.usernameCtrl,
    required this.passwordCtrl,
    required this.displayNameCtrl,
    required this.loading,
    required this.error,
    required this.isDark,
    required this.onSubmit,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TitleBar(title: isRegistering ? 'Veil — Create Account' : 'Veil — Sign In', isDark: isDark),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                Center(
                  child: Column(
                    children: [
                      _AimRunnerIcon(isDark: isDark),
                      const SizedBox(height: 8),
                      Text(
                        'veil',
                        style: TextStyle(
                          fontFamily: 'Arial',
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : AimColors.aimBlue,
                          letterSpacing: 4,
                        ),
                      ),
                      Text(
                        "Signal's security. AIM's soul.",
                        style: TextStyle(
                          fontFamily: 'Arial',
                          fontSize: 10,
                          color: isDark ? Colors.white60 : Colors.grey[600],
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                _FormLabel('Screen Name'),
                const SizedBox(height: 4),
                TextField(
                  controller: usernameCtrl,
                  textInputAction: TextInputAction.next,
                  style: const TextStyle(fontFamily: 'Arial', fontSize: 13),
                  decoration: const InputDecoration(hintText: 'Enter screen name'),
                ),
                const SizedBox(height: 10),
                if (isRegistering) ...[
                  _FormLabel('Display Name'),
                  const SizedBox(height: 4),
                  TextField(
                    controller: displayNameCtrl,
                    textInputAction: TextInputAction.next,
                    style: const TextStyle(fontFamily: 'Arial', fontSize: 13),
                    decoration: const InputDecoration(hintText: 'How others see you'),
                  ),
                  const SizedBox(height: 10),
                ],
                _FormLabel('Password'),
                const SizedBox(height: 4),
                TextField(
                  controller: passwordCtrl,
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => onSubmit(),
                  style: const TextStyle(fontFamily: 'Arial', fontSize: 13),
                  decoration: const InputDecoration(hintText: 'Enter password'),
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    color: Colors.red[100],
                    child: Text(error!, style: const TextStyle(color: Colors.red, fontSize: 11, fontFamily: 'Arial')),
                  ),
                ],
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: loading ? null : onSubmit,
                  child: loading
                      ? const SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(isRegistering ? 'Create Account' : 'Sign In'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: onToggle,
                  child: Text(
                    isRegistering ? 'Already have an account? Sign In' : 'New to Veil? Create an account',
                    style: const TextStyle(fontFamily: 'Arial', fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FormLabel extends StatelessWidget {
  final String text;
  const _FormLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text, style: const TextStyle(fontFamily: 'Arial', fontSize: 11, fontWeight: FontWeight.bold));
  }
}

class _TitleBar extends StatelessWidget {
  final String title;
  final bool isDark;
  const _TitleBar({required this.title, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 24,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [AimColors.darkSurface2, AimColors.darkBackground]
              : [AimColors.aimTitleBar, AimColors.aimTitleBarEnd],
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.centerLeft,
      child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 11, fontFamily: 'Arial', fontWeight: FontWeight.bold)),
    );
  }
}

class _AimRunnerIcon extends StatelessWidget {
  final bool isDark;
  const _AimRunnerIcon({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: isDark ? AimColors.darkSurface : AimColors.aimBlue,
        borderRadius: BorderRadius.circular(30),
      ),
      child: const Icon(Icons.lock, color: Colors.white, size: 30),
    );
  }
}
