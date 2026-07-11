import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/client_manager.dart';
import '../core/conversation_prefs.dart';
import '../core/veil_theme.dart';
import '../core/veil_user_prefs.dart';

class HiddenChatsScreen extends StatefulWidget {
  const HiddenChatsScreen({super.key});
  @override
  State<HiddenChatsScreen> createState() => _HiddenChatsScreenState();
}

class _HiddenChatsScreenState extends State<HiddenChatsScreen> {
  SharedPreferences? _prefs;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    if (mounted) setState(() => _prefs = p);
  }

  Future<void> _unhide(Room room) async {
    final prefs = await ConversationPrefs.load(room.id);
    await prefs.setHidden(false);
    // Force the buddy list to reflect the change immediately.
    if (mounted) {
      context.read<ClientManager>().forceRefresh();
      setState(() {});
    }
  }

  List<Room> _hiddenRooms(List<Room> all) {
    if (_prefs == null) return [];
    return all.where((r) => _prefs!.getBool('conv_${r.id}_hidden') == true).toList();
  }

  @override
  Widget build(BuildContext context) {
    final mgr    = context.watch<ClientManager>();
    final tc     = context.watch<VeilUserPrefs>().colors;
    final topPad = MediaQuery.of(context).padding.top;
    final hidden = _hiddenRooms(mgr.rooms);

    return Scaffold(
      backgroundColor: tc.scaffold,
      body: Column(children: [
        // ── Title bar ─────────────────────────────────────────────────
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [tc.titleStart, tc.titleEnd]),
          ),
          padding: EdgeInsets.fromLTRB(4, topPad + 12, 12, 12),
          child: Row(children: [
            IconButton(
              icon: Icon(Icons.arrow_back, color: tc.titleOnColor, size: 24),
              onPressed: () => context.go('/buddylist'),
            ),
            Expanded(child: Text('Hidden Chats',
                style: TextStyle(color: tc.titleOnColor, fontSize: 18,
                    fontWeight: FontWeight.bold))),
          ]),
        ),

        // ── Body ──────────────────────────────────────────────────────
        Expanded(
          child: _prefs == null
              ? const Center(child: CircularProgressIndicator())
              : hidden.isEmpty
              ? _EmptyHidden(tc: tc)
              : ColoredBox(
                  color: tc.listBg,
                  child: ListView.separated(
                    itemCount: hidden.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1, indent: 66,
                      color: tc.divider == Colors.transparent
                          ? tc.nameText.withAlpha(15) : tc.divider,
                    ),
                    itemBuilder: (ctx, i) {
                      final r       = hidden[i];
                      final name    = r.getLocalizedDisplayname();
                      final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
                      return ListTile(
                        tileColor: tc.rowBg == Colors.transparent ? null : tc.rowBg,
                        leading: Container(
                          width: 44, height: 44,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: VeilThemeColors.avatarGradientFor(initial),
                              begin: Alignment.topLeft, end: Alignment.bottomRight,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(initial,
                              style: TextStyle(color: tc.avatarText, fontSize: 18,
                                  fontWeight: FontWeight.bold)),
                        ),
                        title: Text(name, style: TextStyle(fontSize: 16,
                            color: tc.nameText, fontWeight: FontWeight.w500)),
                        subtitle: Text('Hidden',
                            style: TextStyle(fontSize: 13, color: tc.previewText)),
                        trailing: TextButton.icon(
                          icon: Icon(Icons.visibility, size: 18, color: tc.toolbarActive),
                          label: Text('Unhide',
                              style: TextStyle(fontSize: 14, color: tc.toolbarActive)),
                          onPressed: () => _unhide(r),
                        ),
                        onTap: () => context.go(
                            '/buddylist/chat/${Uri.encodeComponent(r.id)}'),
                      );
                    },
                  ),
                ),
        ),
      ]),
    );
  }
}

class _EmptyHidden extends StatelessWidget {
  final VeilThemeColors tc;
  const _EmptyHidden({required this.tc});

  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.visibility_off_outlined, size: 52, color: tc.previewText),
      const SizedBox(height: 12),
      Text('No hidden conversations',
          style: TextStyle(fontSize: 16, color: tc.previewText)),
      const SizedBox(height: 6),
      Text('Long-press a conversation and tap "Hide"',
          style: TextStyle(fontSize: 14, color: tc.previewText.withAlpha(180))),
    ]),
  );
}
