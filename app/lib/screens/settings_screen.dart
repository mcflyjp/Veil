import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../core/client_manager.dart';
import '../core/aim_theme.dart';
import '../core/veil_theme.dart';
import '../main.dart';
import '../widgets/aim_title_bar.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final mgr = context.watch<ClientManager>();
    final themeNotifier = context.watch<ThemeModeNotifier>();
    final veilTheme = context.watch<VeilThemeNotifier>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final me = mgr.client.userID ?? '';
    final displayName = mgr.myScreenName;

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(MediaQuery.of(context).padding.top + 64),
        child: AimTitleBar(
          title: 'Preferences',
          isDark: isDark,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, size: 24, color: Colors.white),
            onPressed: () => context.pop(),
          ),
        ),
      ),
      body: ListView(
        children: [
          _SectionHeader('My Account'),
          _SettingsTile(
            label: 'Screen name',
            value: me.split(':').first.replaceFirst('@', ''),
          ),
          _SettingsTile(label: 'Display name', value: displayName),
          _SettingsTile(label: 'Server', value: 'veilmsg.com'),
          _SectionHeader('Appearance'),
          SwitchListTile(
            title: const Text('Dark Mode', style: TextStyle(fontFamily: 'Arial', fontSize: 16)),
            value: isDark,
            onChanged: (_) => themeNotifier.toggle(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text('App Theme', style: TextStyle(fontFamily: 'Arial', fontSize: 16, color: Colors.grey.shade600)),
          ),
          ...VeilThemeMode.values.map((m) {
            final tc = VeilThemeColors.forMode(m);
            final selected = veilTheme.mode == m;
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: Row(mainAxisSize: MainAxisSize.min, children: [
                _ThemeSwatch(color: tc.scaffold, size: 22),
                const SizedBox(width: 4),
                _ThemeSwatch(color: tc.titleStart, size: 22),
                const SizedBox(width: 4),
                _ThemeSwatch(color: tc.badgeBg, size: 22),
              ]),
              title: Text(m.label,
                  style: TextStyle(fontFamily: 'Arial', fontSize: 16,
                      fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
              trailing: selected
                  ? Icon(Icons.check_circle, color: tc.badgeBg, size: 22)
                  : null,
              onTap: () => veilTheme.setMode(m),
            );
          }),
          _SectionHeader('Privacy'),
          ListTile(
            title: const Text('End-to-end encryption', style: TextStyle(fontFamily: 'Arial', fontSize: 16)),
            trailing: const Chip(
              label: Text('Enabled', style: TextStyle(fontSize: 14, fontFamily: 'Arial', color: Colors.white)),
              backgroundColor: AimColors.aimOnline,
              padding: EdgeInsets.zero,
              labelPadding: EdgeInsets.symmetric(horizontal: 8),
            ),
          ),
          _SectionHeader('Account'),
          ListTile(
            title: const Text('Sign out', style: TextStyle(fontFamily: 'Arial', fontSize: 16, color: Colors.red)),
            leading: const Icon(Icons.logout, size: 22, color: Colors.red),
            onTap: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Sign out?', style: TextStyle(fontFamily: 'Arial', fontSize: 18)),
                  content: const Text('You will be signed out of Veil on this device.', style: TextStyle(fontFamily: 'Arial', fontSize: 16)),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel', style: TextStyle(fontSize: 16))),
                    ElevatedButton(onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Sign Out', style: TextStyle(fontSize: 16))),
                  ],
                ),
              );
              if (confirm == true && context.mounted) {
                await context.read<ClientManager>().logout();
                if (context.mounted) context.go('/login');
              }
            },
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: isDark ? AimColors.darkSurface2 : AimColors.aimLightBlue,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(text, style: const TextStyle(fontFamily: 'Arial', fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final String label;
  final String value;
  const _SettingsTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(label, style: const TextStyle(fontFamily: 'Arial', fontSize: 14, color: Colors.grey)),
      subtitle: Text(value, style: const TextStyle(fontFamily: 'Arial', fontSize: 16)),
    );
  }
}

class _ThemeSwatch extends StatelessWidget {
  final Color color;
  final double size;
  const _ThemeSwatch({required this.color, required this.size});

  @override
  Widget build(BuildContext context) => Container(
    width: size, height: size,
    decoration: BoxDecoration(
      color: color,
      border: Border.all(color: Colors.grey.shade400, width: 0.5),
      borderRadius: BorderRadius.circular(4),
    ),
  );
}
