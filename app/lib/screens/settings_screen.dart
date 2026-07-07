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
        preferredSize: const Size.fromHeight(48),
        child: AimTitleBar(
          title: 'Preferences',
          isDark: isDark,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, size: 14, color: Colors.white),
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
            dense: true,
            title: const Text('Dark Mode', style: TextStyle(fontFamily: 'Arial', fontSize: 12)),
            value: isDark,
            onChanged: (_) => themeNotifier.toggle(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Text('App Theme', style: TextStyle(fontFamily: 'Arial', fontSize: 11, color: Colors.grey.shade600)),
          ),
          ...VeilThemeMode.values.map((m) {
            final tc = VeilThemeColors.forMode(m);
            final selected = veilTheme.mode == m;
            return ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              leading: Row(mainAxisSize: MainAxisSize.min, children: [
                _ThemeSwatch(color: tc.scaffold, size: 18),
                const SizedBox(width: 3),
                _ThemeSwatch(color: tc.titleStart, size: 18),
                const SizedBox(width: 3),
                _ThemeSwatch(color: tc.badgeBg, size: 18),
              ]),
              title: Text(m.label,
                  style: TextStyle(fontFamily: 'Arial', fontSize: 13,
                      fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
              trailing: selected
                  ? Icon(Icons.check_circle, color: tc.badgeBg, size: 18)
                  : null,
              onTap: () => veilTheme.setMode(m),
            );
          }),
          _SectionHeader('Privacy'),
          ListTile(
            dense: true,
            title: const Text('End-to-end encryption', style: TextStyle(fontFamily: 'Arial', fontSize: 12)),
            trailing: const Chip(
              label: Text('Enabled', style: TextStyle(fontSize: 10, fontFamily: 'Arial', color: Colors.white)),
              backgroundColor: AimColors.aimOnline,
              padding: EdgeInsets.zero,
              labelPadding: EdgeInsets.symmetric(horizontal: 6),
            ),
          ),
          _SectionHeader('Account'),
          ListTile(
            dense: true,
            title: const Text('Sign out', style: TextStyle(fontFamily: 'Arial', fontSize: 12, color: Colors.red)),
            leading: const Icon(Icons.logout, size: 16, color: Colors.red),
            onTap: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Sign out?', style: TextStyle(fontFamily: 'Arial', fontSize: 14)),
                  content: const Text('You will be signed out of Veil on this device.', style: TextStyle(fontFamily: 'Arial', fontSize: 12)),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                    ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sign Out')),
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Text(text, style: const TextStyle(fontFamily: 'Arial', fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
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
      dense: true,
      title: Text(label, style: const TextStyle(fontFamily: 'Arial', fontSize: 11, color: Colors.grey)),
      subtitle: Text(value, style: const TextStyle(fontFamily: 'Arial', fontSize: 12)),
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
