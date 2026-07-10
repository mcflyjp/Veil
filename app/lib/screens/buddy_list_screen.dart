import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../core/client_manager.dart';
import '../core/aim_theme.dart';
import '../core/conversation_prefs.dart';
import '../core/veil_theme.dart';
import '../core/veil_user_prefs.dart';

class BuddyListScreen extends StatefulWidget {
  const BuddyListScreen({super.key});
  @override
  State<BuddyListScreen> createState() => _BuddyListScreenState();
}

class _BuddyListScreenState extends State<BuddyListScreen> {
  final Map<String, bool> _mutedCache = {};

  @override
  void initState() {
    super.initState();
    _warmMutedCache();
  }

  Future<void> _warmMutedCache() async {
    final p = await SharedPreferences.getInstance();
    final map = <String, bool>{};
    for (final key in p.getKeys()) {
      if (key.startsWith('conv_') && key.endsWith('_muted')) {
        final roomId = key.substring(5, key.length - 6);
        map[roomId] = p.getBool(key) ?? false;
      }
    }
    if (mounted) setState(() => _mutedCache.addAll(map));
  }

  Future<bool> _getMuted(String roomId) async {
    if (_mutedCache.containsKey(roomId)) return _mutedCache[roomId]!;
    final p = await SharedPreferences.getInstance();
    final v = p.getBool('conv_${roomId}_muted') ?? false;
    _mutedCache[roomId] = v;
    return v;
  }

  Future<void> _setMuted(String roomId, bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('conv_${roomId}_muted', v);
    setState(() => _mutedCache[roomId] = v);
  }

  Future<void> _confirmDelete(BuildContext ctx, Room room, VeilThemeColors tc) async {
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (_) => AlertDialog(
        backgroundColor: tc.rowBg == Colors.transparent ? const Color(0xFF1A1A30) : tc.rowBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(tc.rowRadius)),
        title: Text('Delete conversation?',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: tc.nameText)),
        content: Text(
            'This will leave the conversation with ${room.getLocalizedDisplayname()} and remove it from your list.',
            style: TextStyle(fontSize: 14, color: tc.previewText)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel', style: TextStyle(fontSize: 14, color: tc.toolbarActive))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(fontSize: 14, color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try { await room.leave(); } catch (_) {}
      setState(() {});
    }
  }

  void _showContextMenu(BuildContext ctx, Room room) async {
    final prefs = await ConversationPrefs.load(room.id);
    if (!ctx.mounted) return;
    final tc = ctx.read<VeilUserPrefs>().colors;

    await showModalBottomSheet(
      context: ctx,
      backgroundColor: tc.useGlass ? const Color(0xFF0F0F2A) : tc.scaffold,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      builder: (_) => _ConvContextMenu(
        room: room, prefs: prefs,
        tc: tc,
        onMuteToggle: (v) => _setMuted(room.id, v),
        onDelete: () => _confirmDelete(ctx, room, tc),
        onRefresh: () => setState(() {}),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mgr = context.watch<ClientManager>();
    final tc  = context.watch<VeilUserPrefs>().colors;
    final vtn = context.read<VeilUserPrefs>();
    final rooms = mgr.rooms;
    final invites = mgr.inviteRooms;
    final screenName = mgr.myScreenName;

    Widget content = Column(
      children: [
        // ── Title bar ───────────────────────────────────────────────
        _TitleBar(tc: tc, vtn: vtn, screenName: screenName, onNew: () => context.go('/buddylist/new')),

        // ── Buddy list body ─────────────────────────────────────────
        Expanded(
          child: _buildList(context, tc, rooms, invites),
        ),

        // ── Bottom toolbar ──────────────────────────────────────────
        _BottomToolbar(
          tc: tc,
          onIM: () => context.go('/buddylist/new'),
          onSettings: () => context.go('/buddylist/settings'),
          onSignOff: () => context.read<ClientManager>().logout(),
        ),
      ],
    );

    // Glass theme: stack glow orb behind content
    if (tc.showGlow) {
      content = Stack(children: [
        Positioned(top: 40, left: -80,
          child: _GlowOrb(color: tc.glowColor, size: 360)),
        Positioned(bottom: 100, right: -60,
          child: _GlowOrb(color: tc.glowColor.withAlpha(100), size: 260)),
        content,
      ]);
    }

    return ColoredBox(color: tc.scaffold, child: content);
  }

  Widget _buildList(BuildContext context, VeilThemeColors tc, List<Room> rooms, List<Room> invites) {
    if (rooms.isEmpty && invites.isEmpty) {
      return ColoredBox(
        color: tc.listBg,
        child: _EmptyState(tc: tc, onNew: () => context.go('/buddylist/new')),
      );
    }

    return ColoredBox(
      color: tc.listBg,
      child: ListView(
        padding: tc.roundedRows ? const EdgeInsets.symmetric(horizontal: 12, vertical: 8) : EdgeInsets.zero,
        children: [
          // ── Message Requests ──────────────────────────────────────
          if (invites.isNotEmpty) ...[
            _RequestsHeader(tc: tc, count: invites.length),
            ...invites.map((r) => _InviteRow(
              room: r,
              tc: tc,
              onAccept: () async {
                try { await r.join(); } catch (_) {}
              },
              onDecline: () async {
                try { await r.leave(); } catch (_) {}
              },
            )),
          ],
          // ── Conversations ─────────────────────────────────────────
          if (rooms.isNotEmpty) ...[
            if (!tc.useGlass) _SectionHeader(tc: tc, count: rooms.length),
            if (tc.useGlass) const SizedBox(height: 4),
            ...rooms.map((r) => _BuddyRow(
              room: r,
              tc: tc,
              muted: _mutedCache[r.id] ?? false,
              onDelete: () => _confirmDelete(context, r, tc),
              onMuteToggle: () => _getMuted(r.id).then((cur) => _setMuted(r.id, !cur)),
              onLongPress: () => _showContextMenu(context, r),
            )),
          ],
        ],
      ),
    );
  }
}

// ── Glow orb (Glass theme only) ────────────────────────────────────────────────

class _GlowOrb extends StatelessWidget {
  final Color color;
  final double size;
  const _GlowOrb({required this.color, required this.size});

  @override
  Widget build(BuildContext context) => Container(
    width: size, height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(colors: [color.withAlpha(80), Colors.transparent]),
    ),
  );
}

// ── Title bar ──────────────────────────────────────────────────────────────────

class _TitleBar extends StatelessWidget {
  final VeilThemeColors tc;
  final VeilUserPrefs vtn;
  final String screenName;
  final VoidCallback onNew;
  const _TitleBar({required this.tc, required this.vtn, required this.screenName, required this.onNew});

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    Widget bar = Container(
      padding: EdgeInsets.fromLTRB(16, topPad + 16, 8, 16),
      child: Row(children: [
        Icon(Icons.lock, color: Colors.white.withAlpha(230), size: 22),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Veil',
              style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
          Text(screenName,
              style: TextStyle(color: Colors.white.withAlpha(200), fontSize: 16),
              overflow: TextOverflow.ellipsis),
        ])),
        // Theme cycle button
        _TitleIconBtn(
          icon: vtn.theme.icon,
          tooltip: 'Theme: ${vtn.theme.label}',
          onTap: () {
            vtn.cycleTheme();
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Theme: ${vtn.theme.label}'),
              duration: const Duration(seconds: 1),
              behavior: SnackBarBehavior.floating,
            ));
          },
        ),
        _TitleIconBtn(icon: Icons.edit_note, tooltip: 'New message', onTap: onNew),
        _TitleIconBtn(icon: Icons.settings, tooltip: 'Settings',
            onTap: () => context.go('/buddylist/settings')),
      ]),
    );

    if (tc.useGlass) {
      return ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            decoration: BoxDecoration(
              color: tc.titleStart,
              border: Border(bottom: BorderSide(color: Colors.white.withAlpha(20))),
            ),
            child: bar,
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [tc.titleStart, tc.titleEnd]),
      ),
      child: bar,
    );
  }
}

class _TitleIconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _TitleIconBtn({required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Icon(icon, color: Colors.white.withAlpha(220), size: 24),
      ),
    ),
  );
}

// ── Section header ─────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final VeilThemeColors tc;
  final int count;
  const _SectionHeader({required this.tc, required this.count});

  @override
  Widget build(BuildContext context) => Container(
    color: tc.sectionBg,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
    child: Row(children: [
      const Icon(Icons.arrow_drop_down, color: Colors.white, size: 20),
      Text('Conversations ($count)',
          style: TextStyle(color: tc.sectionText, fontSize: 16, fontWeight: FontWeight.bold)),
    ]),
  );
}

// ── Buddy row ──────────────────────────────────────────────────────────────────

class _BuddyRow extends StatelessWidget {
  final Room room;
  final VeilThemeColors tc;
  final bool muted;
  final VoidCallback onDelete;
  final VoidCallback onMuteToggle;
  final VoidCallback onLongPress;
  const _BuddyRow({
    required this.room, required this.tc, required this.muted,
    required this.onDelete, required this.onMuteToggle, required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final name  = room.getLocalizedDisplayname();
    final last  = room.lastEvent;
    final unread = room.notificationCount > 0;
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    final rowPadding = tc.roundedRows
        ? const EdgeInsets.only(bottom: 8)
        : EdgeInsets.zero;

    return Padding(
      padding: rowPadding,
      child: Slidable(
        key: ValueKey(room.id),
        startActionPane: ActionPane(
          motion: const DrawerMotion(),
          extentRatio: 0.25,
          children: [
            SlidableAction(
              onPressed: (_) => onMuteToggle(),
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              icon: muted ? Icons.volume_up : Icons.volume_off,
              label: muted ? 'Unmute' : 'Mute',
            ),
          ],
        ),
        endActionPane: ActionPane(
          motion: const DrawerMotion(),
          extentRatio: 0.25,
          children: [
            SlidableAction(
              onPressed: (_) => onDelete(),
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              icon: Icons.delete,
              label: 'Delete',
            ),
          ],
        ),
        child: GestureDetector(
          onLongPress: onLongPress,
          child: InkWell(
            onTap: () => context.go('/buddylist/chat/${Uri.encodeComponent(room.id)}'),
            borderRadius: tc.roundedRows ? BorderRadius.circular(tc.rowRadius) : BorderRadius.zero,
            child: _buildRowContent(context, name, initial, last, unread),
          ),
        ),
      ),
    );
  }

  Widget _buildRowContent(BuildContext context, String name, String initial, dynamic last, bool unread) {
    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: tc.roundedRows
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(tc.rowRadius),
              border: tc.useGlass
                  ? Border.all(color: Colors.white.withAlpha(20))
                  : (tc.divider == Colors.transparent ? null
                      : Border.all(color: tc.divider, width: 0.5)),
              color: tc.useGlass ? null : tc.rowBg,
              boxShadow: tc.divider != Colors.transparent && !tc.useGlass
                  ? [BoxShadow(color: Colors.black.withAlpha(18), blurRadius: 6, offset: const Offset(0, 2))]
                  : null,
            )
          : BoxDecoration(
              color: tc.rowBg,
              border: Border(bottom: BorderSide(color: tc.divider, width: 0.5)),
            ),
      child: Row(children: [
        _Avatar(initial: initial, tc: tc, isGroup: !room.isDirectChat),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Row(children: [
              Flexible(child: Text(name,
                style: TextStyle(fontSize: 16, fontWeight: unread ? FontWeight.bold : FontWeight.w500,
                    color: tc.nameText),
                overflow: TextOverflow.ellipsis)),
              if (muted) ...[
                const SizedBox(width: 4),
                Icon(Icons.volume_off, size: 13, color: Colors.orange.shade400),
              ],
            ])),
            if (last != null)
              Text(timeago.format(last.originServerTs, allowFromNow: true),
                  style: TextStyle(fontSize: 14, color: tc.timestampText)),
            if (unread) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: tc.badgeBg, borderRadius: BorderRadius.circular(12)),
                child: Text('${room.notificationCount}',
                    style: TextStyle(color: tc.badgeText, fontSize: 13, fontWeight: FontWeight.bold)),
              ),
            ],
          ]),
          const SizedBox(height: 2),
          if (last != null)
            Text(last.body ?? '',
              style: TextStyle(fontSize: 16, color: tc.previewText,
                  fontWeight: unread ? FontWeight.bold : FontWeight.normal),
              overflow: TextOverflow.ellipsis, maxLines: 1),
        ])),
      ]),
    );

    if (tc.useGlass) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(tc.rowRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            decoration: BoxDecoration(
              color: tc.rowBg,
              borderRadius: BorderRadius.circular(tc.rowRadius),
              border: Border.all(color: Colors.white.withAlpha(20)),
            ),
            child: content,
          ),
        ),
      );
    }

    return content;
  }
}

// ── Avatar ─────────────────────────────────────────────────────────────────────

class _Avatar extends StatelessWidget {
  final String initial;
  final VeilThemeColors tc;
  // Groups don't get a presence dot — only DMs do
  final bool isGroup;
  const _Avatar({required this.initial, required this.tc, this.isGroup = false});

  @override
  Widget build(BuildContext context) {
    final child = Stack(children: [
      Container(
        width: 46, height: 46,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: tc.gradientAvatar
              ? LinearGradient(
                  colors: VeilThemeColors.avatarGradientFor(initial),
                  begin: Alignment.topLeft, end: Alignment.bottomRight)
              : null,
          color: tc.gradientAvatar ? null : tc.solidAvatarBg,
        ),
        child: Center(child: Text(initial,
            style: TextStyle(color: tc.avatarText, fontSize: 19, fontWeight: FontWeight.bold))),
      ),
      if (!isGroup)
        Positioned(bottom: 1, right: 1,
          child: Container(
            width: 12, height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AimColors.online,
              border: Border.all(color: tc.presenceBorder, width: 1.5),
            ),
          ),
        ),
    ]);

    return SizedBox(width: 46, height: 46, child: child);
  }
}

// ── Bottom toolbar ─────────────────────────────────────────────────────────────

class _BottomToolbar extends StatelessWidget {
  final VeilThemeColors tc;
  final VoidCallback onIM;
  final VoidCallback onSettings;
  final VoidCallback onSignOff;
  const _BottomToolbar({required this.tc, required this.onIM, required this.onSettings, required this.onSignOff});

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    Widget bar = Row(children: [
      _ToolbarBtn(icon: Icons.message, label: 'IM', tc: tc, onTap: onIM),
      _ToolbarBtn(icon: Icons.settings, label: 'Settings', tc: tc, onTap: onSettings),
      const Spacer(),
      _ToolbarBtn(icon: Icons.logout, label: 'Sign Off', tc: tc, onTap: onSignOff),
    ]);

    if (tc.useGlass) {
      return ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: EdgeInsets.only(left: 8, right: 8, bottom: bottomPad),
            height: 68 + bottomPad,
            decoration: BoxDecoration(
              color: tc.toolbarBg,
              border: Border(top: BorderSide(color: Colors.white.withAlpha(20))),
            ),
            child: bar,
          ),
        ),
      );
    }

    return Container(
      height: 68 + bottomPad,
      color: tc.toolbarBg,
      padding: EdgeInsets.only(left: 8, right: 8, bottom: bottomPad),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: tc.divider == Colors.transparent
            ? Colors.white.withAlpha(20) : tc.divider)),
      ),
      child: bar,
    );
  }
}

class _ToolbarBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VeilThemeColors tc;
  final VoidCallback onTap;
  const _ToolbarBtn({required this.icon, required this.label, required this.tc, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(8),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 26, color: tc.toolbarText),
        const SizedBox(height: 3),
        Text(label, style: TextStyle(fontSize: 16, color: tc.toolbarText)),
      ]),
    ),
  );
}

// ── Context menu bottom sheet ──────────────────────────────────────────────────

class _ConvContextMenu extends StatefulWidget {
  final Room room;
  final ConversationPrefs prefs;
  final VeilThemeColors tc;
  final ValueChanged<bool> onMuteToggle;
  final VoidCallback onDelete;
  final VoidCallback onRefresh;
  const _ConvContextMenu({
    required this.room, required this.prefs, required this.tc,
    required this.onMuteToggle, required this.onDelete, required this.onRefresh,
  });
  @override
  State<_ConvContextMenu> createState() => _ConvContextMenuState();
}

class _ConvContextMenuState extends State<_ConvContextMenu> {
  late bool _muted;
  late int _disappearing;
  late String _themeKey;

  @override
  void initState() {
    super.initState();
    _muted        = widget.prefs.muted;
    _disappearing = widget.prefs.disappearingSecs;
    _themeKey     = widget.prefs.themeKey;
  }

  @override
  Widget build(BuildContext context) {
    final tc = widget.tc;
    final name = widget.room.getLocalizedDisplayname();

    return SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Header
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [tc.titleStart, tc.titleEnd]),
          ),
          child: Text(name, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis),
        ),

        _MenuTile(icon: _muted ? Icons.volume_up : Icons.volume_off,
          iconColor: _muted ? Colors.orange : tc.toolbarText,
          label: _muted ? 'Unmute Conversation' : 'Mute Conversation',
          textColor: tc.nameText,
          onTap: () async {
            final v = !_muted;
            await widget.prefs.setMuted(v);
            widget.onMuteToggle(v);
            setState(() => _muted = v);
          },
        ),
        _MenuTile(icon: Icons.visibility_off, iconColor: tc.toolbarText,
          label: 'Hide Conversation', textColor: tc.nameText,
          onTap: () async {
            await widget.prefs.setHidden(true);
            Navigator.pop(context);
            widget.onRefresh();
          },
        ),
        _MenuTile(icon: Icons.timer, iconColor: tc.toolbarText,
          label: 'Disappearing Messages', textColor: tc.nameText,
          subtitle: _disappearing == 0 ? 'Off'
              : _disappearing < 3600 ? '${_disappearing ~/ 60}m'
              : '${_disappearing ~/ 3600}h',
          onTap: () => _showDisappearingPicker(context),
        ),
        _MenuTile(icon: Icons.palette, iconColor: tc.toolbarText,
          label: 'Conversation Theme', textColor: tc.nameText,
          subtitle: ConversationPrefs.themes[_themeKey]?.label ?? 'Classic AIM',
          onTap: () => _showThemePicker(context),
        ),
        const Divider(height: 1),
        _MenuTile(icon: Icons.delete_forever, iconColor: Colors.red,
          label: 'Delete Conversation', textColor: Colors.red,
          onTap: () { Navigator.pop(context); widget.onDelete(); },
        ),
        const SizedBox(height: 8),
      ]),
    );
  }

  void _showDisappearingPicker(BuildContext ctx) async {
    final options = [(0,'Off'),(30,'30 seconds'),(300,'5 minutes'),(3600,'1 hour'),(86400,'24 hours'),(604800,'7 days')];
    await showDialog(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(widget.tc.rowRadius)),
        title: const Text('Disappearing Messages', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: Column(mainAxisSize: MainAxisSize.min, children: options.map((o) {
          final (secs, label) = o;
          return RadioListTile<int>(
            value: secs, groupValue: _disappearing,
            title: Text(label, style: const TextStyle(fontSize: 16)),
            onChanged: (v) async {
              if (v == null) return;
              await widget.prefs.setDisappearing(v);
              setState(() => _disappearing = v);
              Navigator.pop(dialogCtx);
            },
          );
        }).toList()),
      ),
    );
  }

  void _showThemePicker(BuildContext ctx) async {
    await showDialog(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(widget.tc.rowRadius)),
        title: const Text('Conversation Theme', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: Column(mainAxisSize: MainAxisSize.min,
          children: ConversationPrefs.themes.entries.map((e) => RadioListTile<String>(
            value: e.key, groupValue: _themeKey,
            title: Row(children: [
              Container(width: 18, height: 18,
                decoration: BoxDecoration(color: e.value.chatBg, border: Border.all(color: Colors.grey))),
              const SizedBox(width: 8),
              Text(e.value.label, style: const TextStyle(fontSize: 16)),
            ]),
            onChanged: (v) async {
              if (v == null) return;
              await widget.prefs.setTheme(v);
              setState(() => _themeKey = v);
              Navigator.pop(dialogCtx);
            },
          )).toList(),
        ),
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String? subtitle;
  final Color textColor;
  final VoidCallback onTap;
  const _MenuTile({required this.icon, required this.iconColor, required this.label,
      required this.textColor, required this.onTap, this.subtitle});

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(children: [
        Icon(icon, size: 26, color: iconColor),
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 16, color: textColor, fontWeight: FontWeight.w500)),
          if (subtitle != null)
            Text(subtitle!, style: TextStyle(fontSize: 16, color: textColor.withAlpha(153))),
        ])),
      ]),
    ),
  );
}

// ── Message Requests section header ───────────────────────────────────────────

class _RequestsHeader extends StatelessWidget {
  final VeilThemeColors tc;
  final int count;
  const _RequestsHeader({required this.tc, required this.count});

  @override
  Widget build(BuildContext context) => Container(
    color: Colors.orange.shade700,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
    child: Row(children: [
      const Icon(Icons.mail_outline, color: Colors.white, size: 18),
      const SizedBox(width: 6),
      Text('Message Requests ($count)',
          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
    ]),
  );
}

// ── Invite row ─────────────────────────────────────────────────────────────────

class _InviteRow extends StatefulWidget {
  final Room room;
  final VeilThemeColors tc;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  const _InviteRow({required this.room, required this.tc,
      required this.onAccept, required this.onDecline});

  @override
  State<_InviteRow> createState() => _InviteRowState();
}

class _InviteRowState extends State<_InviteRow> {
  bool _busy = false;

  String get _inviterName {
    final myId = widget.room.client.userID ?? '';
    final inviterEvent = widget.room.getState(EventTypes.RoomMember, myId);
    final inviterId = inviterEvent?.senderId ?? '';
    return inviterId.isNotEmpty
        ? inviterId.split(':').first.replaceFirst('@', '')
        : widget.room.getLocalizedDisplayname();
  }

  @override
  Widget build(BuildContext context) {
    final tc = widget.tc;
    final name = _inviterName;
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return Container(
      color: tc.rowBg == Colors.transparent ? Colors.transparent : tc.rowBg.withAlpha(230),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(children: [
        // Avatar
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.orange.shade600,
          ),
          alignment: Alignment.center,
          child: Text(initial,
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(width: 12),
        // Name + prompt
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: tc.nameText),
            overflow: TextOverflow.ellipsis),
          Text('wants to message you',
            style: TextStyle(fontSize: 13, color: tc.previewText)),
        ])),
        const SizedBox(width: 8),
        // Decline
        _busy
            ? const SizedBox(width: 22, height: 22,
                child: CircularProgressIndicator(strokeWidth: 2))
            : Row(mainAxisSize: MainAxisSize.min, children: [
                _ActionBtn(
                  label: 'Decline',
                  color: Colors.red,
                  onTap: () async {
                    setState(() => _busy = true);
                    widget.onDecline();
                  },
                ),
                const SizedBox(width: 6),
                _ActionBtn(
                  label: 'Accept',
                  color: Colors.green.shade600,
                  onTap: () async {
                    setState(() => _busy = true);
                    widget.onAccept();
                  },
                ),
              ]),
      ]),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionBtn({required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label,
        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
    ),
  );
}

// ── Empty state ────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final VeilThemeColors tc;
  final VoidCallback onNew;
  const _EmptyState({required this.tc, required this.onNew});

  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.people_outline, size: 60, color: tc.previewText),
      const SizedBox(height: 12),
      Text('No conversations yet.', style: TextStyle(fontSize: 16, color: tc.previewText)),
      const SizedBox(height: 16),
      ElevatedButton(
        onPressed: onNew,
        style: ElevatedButton.styleFrom(
          backgroundColor: tc.badgeBg,
          foregroundColor: tc.badgeText,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(tc.rowRadius)),
          textStyle: const TextStyle(fontSize: 15),
        ),
        child: const Text('Send Instant Message'),
      ),
    ]),
  );
}
