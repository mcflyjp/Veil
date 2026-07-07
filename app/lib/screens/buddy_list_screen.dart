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

/// Pure column — no Scaffold. SplitShell provides the Scaffold wrapping.
class BuddyListScreen extends StatefulWidget {
  const BuddyListScreen({super.key});
  @override
  State<BuddyListScreen> createState() => _BuddyListScreenState();
}

class _BuddyListScreenState extends State<BuddyListScreen> {
  // roomId → muted state (in-memory cache so rows rebuild instantly)
  final Map<String, bool> _mutedCache = {};

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

  Future<void> _confirmDelete(BuildContext ctx, Room room) async {
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (_) => AlertDialog(
        backgroundColor: AimColors.buddyListBg,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: const Text('Delete conversation?',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: Text('This will leave the conversation with ${room.getLocalizedDisplayname()} and remove it from your list.',
            style: const TextStyle(fontSize: 14)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(fontSize: 14))),
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
    final isDark = Theme.of(ctx).brightness == Brightness.dark;

    await showModalBottomSheet(
      context: ctx,
      backgroundColor: isDark ? AimColors.darkBuddyBg : AimColors.buddyListBg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      builder: (_) => _ConvContextMenu(
        room: room,
        prefs: prefs,
        onMuteToggle: (v) => _setMuted(room.id, v),
        onDelete: () => _confirmDelete(ctx, room),
        onRefresh: () => setState(() {}),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mgr = context.watch<ClientManager>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final rooms = mgr.rooms;
    final screenName = mgr.myScreenName;

    return Column(
      children: [
          // ── AIM-style title bar ──────────────────────────────────────
          _AimTitleBar(title: 'Buddy List', isDark: isDark, actions: [
            _TitleBarButton(icon: Icons.settings, tooltip: 'Settings',
                onTap: () => context.go('/buddylist/settings')),
          ]),

          // ── Screen name + status strip ───────────────────────────────
          Container(
            color: isDark ? AimColors.darkSectionBg : AimColors.titleBarStart,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(children: [
              _PresenceDot(online: true),
              const SizedBox(width: 8),
              Expanded(child: Text(screenName,
                style: const TextStyle(color: Colors.white, fontSize: 16,
                    fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis)),
              InkWell(
                onTap: () => context.go('/buddylist/new'),
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(Icons.edit_note, color: Colors.white, size: 26),
                ),
              ),
            ]),
          ),

          // ── Buddy list body ─────────────────────────────────────────
          Expanded(
            child: Container(
              color: isDark ? AimColors.darkBuddyBg : AimColors.buddyListBg,
              child: rooms.isEmpty
                  ? _EmptyState(onNew: () => context.go('/buddylist/new'))
                  : ListView(children: [
                      _SectionHeader('Conversations (${rooms.length})', isDark: isDark),
                      ...rooms.map((r) => _BuddyRow(
                        room: r,
                        isDark: isDark,
                        muted: _mutedCache[r.id] ?? false,
                        onDelete: () => _confirmDelete(context, r),
                        onMuteToggle: () => _getMuted(r.id).then((cur) => _setMuted(r.id, !cur)),
                        onLongPress: () => _showContextMenu(context, r),
                      )),
                    ]),
            ),
          ),

          // ── Bottom toolbar ──────────────────────────────────────────
          Container(
            height: 60,
            color: isDark ? const Color(0xFF111111) : AimColors.buddyListBg,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(
                  color: isDark ? AimColors.darkBorder : AimColors.winBorder)),
            ),
            child: Row(children: [
              _ToolbarButton(icon: Icons.message, label: 'IM',
                  onTap: () => context.go('/buddylist/new')),
              _ToolbarButton(icon: Icons.people, label: 'Chat',
                  onTap: () => context.go('/buddylist/new')),
              const Spacer(),
              _ToolbarButton(icon: Icons.logout, label: 'Sign Off',
                  onTap: () => context.read<ClientManager>().logout()),
            ]),
          ),
        ],
    );
  }
}

// ── Per-conversation context menu (bottom sheet) ───────────────────────────

class _ConvContextMenu extends StatefulWidget {
  final Room room;
  final ConversationPrefs prefs;
  final ValueChanged<bool> onMuteToggle;
  final VoidCallback onDelete;
  final VoidCallback onRefresh;
  const _ConvContextMenu({
    required this.room, required this.prefs,
    required this.onMuteToggle, required this.onDelete,
    required this.onRefresh,
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
    _muted = widget.prefs.muted;
    _disappearing = widget.prefs.disappearingSecs;
    _themeKey = widget.prefs.themeKey;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AimColors.darkText : Colors.black;
    final name = widget.room.getLocalizedDisplayname();

    return SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Header
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: isDark
                ? [AimColors.darkTitleBar, const Color(0xFF1A3A6A)]
                : [AimColors.titleBarStart, AimColors.titleBarEnd]),
          ),
          child: Text(name,
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            overflow: TextOverflow.ellipsis),
        ),

        // Mute toggle
        _MenuTile(
          icon: _muted ? Icons.volume_off : Icons.volume_up,
          iconColor: _muted ? Colors.orange : (isDark ? Colors.grey[300]! : Colors.black87),
          label: _muted ? 'Unmute Conversation' : 'Mute Conversation',
          textColor: textColor,
          onTap: () async {
            final newVal = !_muted;
            await widget.prefs.setMuted(newVal);
            widget.onMuteToggle(newVal);
            setState(() => _muted = newVal);
          },
        ),

        // Hide
        _MenuTile(
          icon: Icons.visibility_off,
          iconColor: isDark ? Colors.grey[300]! : Colors.black87,
          label: 'Hide Conversation',
          textColor: textColor,
          onTap: () async {
            await widget.prefs.setHidden(true);
            Navigator.pop(context);
            widget.onRefresh();
          },
        ),

        // Disappearing messages
        _MenuTile(
          icon: Icons.timer,
          iconColor: isDark ? Colors.grey[300]! : Colors.black87,
          label: 'Disappearing Messages',
          subtitle: _disappearing == 0 ? 'Off'
              : _disappearing < 3600 ? '${_disappearing ~/ 60}m'
              : '${_disappearing ~/ 3600}h',
          textColor: textColor,
          onTap: () => _showDisappearingPicker(context),
        ),

        // Theme settings
        _MenuTile(
          icon: Icons.palette,
          iconColor: isDark ? Colors.grey[300]! : Colors.black87,
          label: 'Conversation Theme',
          subtitle: ConversationPrefs.themes[_themeKey]?.label ?? 'Classic AIM',
          textColor: textColor,
          onTap: () => _showThemePicker(context),
        ),

        const Divider(height: 1),

        // Delete
        _MenuTile(
          icon: Icons.delete_forever,
          iconColor: Colors.red,
          label: 'Delete Conversation',
          textColor: Colors.red,
          onTap: () {
            Navigator.pop(context);
            widget.onDelete();
          },
        ),

        const SizedBox(height: 8),
      ]),
    );
  }

  void _showDisappearingPicker(BuildContext ctx) async {
    final options = [
      (0, 'Off'),
      (30, '30 seconds'),
      (300, '5 minutes'),
      (3600, '1 hour'),
      (86400, '24 hours'),
      (604800, '7 days'),
    ];
    await showDialog(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: Theme.of(ctx).brightness == Brightness.dark
            ? AimColors.darkBuddyBg : AimColors.buddyListBg,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: const Text('Disappearing Messages', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: Column(mainAxisSize: MainAxisSize.min, children: options.map((o) {
          final (secs, label) = o;
          return RadioListTile<int>(
            value: secs,
            groupValue: _disappearing,
            title: Text(label, style: const TextStyle(fontSize: 15)),
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
        backgroundColor: Theme.of(ctx).brightness == Brightness.dark
            ? AimColors.darkBuddyBg : AimColors.buddyListBg,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: const Text('Conversation Theme', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: Column(mainAxisSize: MainAxisSize.min,
          children: ConversationPrefs.themes.entries.map((e) {
            return RadioListTile<String>(
              value: e.key,
              groupValue: _themeKey,
              title: Row(children: [
                Container(width: 18, height: 18,
                  decoration: BoxDecoration(color: e.value.chatBg,
                    border: Border.all(color: Colors.grey)),
                ),
                const SizedBox(width: 8),
                Text(e.value.label, style: const TextStyle(fontSize: 15)),
              ]),
              onChanged: (v) async {
                if (v == null) return;
                await widget.prefs.setTheme(v);
                setState(() => _themeKey = v);
                Navigator.pop(dialogCtx);
              },
            );
          }).toList(),
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
  const _MenuTile({
    required this.icon, required this.iconColor,
    required this.label, required this.textColor,
    required this.onTap, this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(children: [
          Icon(icon, size: 26, color: iconColor),
          const SizedBox(width: 16),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 16, color: textColor, fontWeight: FontWeight.w500)),
              if (subtitle != null)
                Text(subtitle!, style: TextStyle(fontSize: 13, color: textColor.withAlpha(153))),
            ],
          )),
        ]),
      ),
    );
  }
}

// ── Title bar ──────────────────────────────────────────────────────────────

class _AimTitleBar extends StatelessWidget {
  final String title;
  final bool isDark;
  final List<Widget> actions;
  const _AimTitleBar({required this.title, required this.isDark, this.actions = const []});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: isDark
            ? [AimColors.darkTitleBar, const Color(0xFF1A3A6A)]
            : [AimColors.titleBarStart, AimColors.titleBarEnd]),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(children: [
        const Icon(Icons.lock, color: Colors.white, size: 20),
        const SizedBox(width: 6),
        Expanded(child: Text('Veil — $title',
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold))),
        ...actions,
      ]),
    );
  }
}

class _TitleBarButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _TitleBarButton({required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(padding: const EdgeInsets.all(8),
        child: Icon(icon, color: Colors.white, size: 22)),
  );
}

// ── Section header ─────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String text;
  final bool isDark;
  const _SectionHeader(this.text, {required this.isDark});

  @override
  Widget build(BuildContext context) => Container(
    color: isDark ? AimColors.darkSectionBg : AimColors.sectionHeaderBg,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    child: Row(children: [
      const Icon(Icons.arrow_drop_down, color: Colors.white, size: 22),
      Text(text, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
    ]),
  );
}

// ── Buddy row with swipe actions ───────────────────────────────────────────

class _BuddyRow extends StatelessWidget {
  final Room room;
  final bool isDark;
  final bool muted;
  final VoidCallback onDelete;
  final VoidCallback onMuteToggle;
  final VoidCallback onLongPress;
  const _BuddyRow({
    required this.room, required this.isDark, required this.muted,
    required this.onDelete, required this.onMuteToggle, required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final name = room.getLocalizedDisplayname();
    final last = room.lastEvent;
    final unread = room.notificationCount > 0;

    return Slidable(
      key: ValueKey(room.id),
      // Swipe right → mute/unmute
      startActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.28,
        children: [
          SlidableAction(
            onPressed: (_) => onMuteToggle(),
            backgroundColor: Colors.orange,
            foregroundColor: Colors.white,
            icon: muted ? Icons.volume_up : Icons.volume_off,
            label: muted ? 'Unmute' : 'Mute',
            padding: const EdgeInsets.all(0),
          ),
        ],
      ),
      // Swipe left → delete
      endActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.28,
        children: [
          SlidableAction(
            onPressed: (_) => onDelete(),
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
            icon: Icons.delete,
            label: 'Delete',
            padding: const EdgeInsets.all(0),
          ),
        ],
      ),
      child: GestureDetector(
        onLongPress: onLongPress,
        child: InkWell(
          onTap: () => context.go('/buddylist/chat/${Uri.encodeComponent(room.id)}'),
          child: Container(
            color: isDark ? AimColors.darkBuddyBg : Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(
                  color: isDark ? AimColors.darkBorder : const Color(0xFFDDDDDD), width: 0.5)),
            ),
            child: Row(children: [
              // Avatar circle
              Container(
                width: 46, height: 46,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDark ? AimColors.darkSectionBg : AimColors.sectionHeaderBg,
                ),
                child: Center(child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                )),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(child: Row(children: [
                      Flexible(child: Text(name,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: unread ? FontWeight.bold : FontWeight.normal,
                          color: isDark ? AimColors.darkText : Colors.black,
                        ),
                        overflow: TextOverflow.ellipsis)),
                      if (muted) ...[
                        const SizedBox(width: 6),
                        Icon(Icons.volume_off, size: 15, color: Colors.orange.shade400),
                      ],
                    ])),
                    if (last != null)
                      Text(timeago.format(last.originServerTs, allowFromNow: true),
                        style: TextStyle(fontSize: 12, color: isDark ? Colors.grey[500] : Colors.grey[600])),
                    if (unread) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF17369C),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text('${room.notificationCount}',
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ]),
                  const SizedBox(height: 2),
                  if (last != null)
                    Text(last.body ?? '',
                      style: TextStyle(fontSize: 13,
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                        fontWeight: unread ? FontWeight.bold : FontWeight.normal),
                      overflow: TextOverflow.ellipsis, maxLines: 1),
                ],
              )),
            ]),
          ),
        ),
      ),
    );
  }
}

// ── Presence dot ───────────────────────────────────────────────────────────

class _PresenceDot extends StatelessWidget {
  final bool online;
  const _PresenceDot({required this.online});

  @override
  Widget build(BuildContext context) => Container(
    width: 12, height: 12,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: online ? AimColors.online : AimColors.offline,
      border: Border.all(color: Colors.white, width: 1),
    ),
  );
}

// ── Bottom toolbar button ──────────────────────────────────────────────────

class _ToolbarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ToolbarButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 24, color: isDark ? Colors.grey[300] : Colors.black87),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 12, color: isDark ? Colors.grey[300] : Colors.black87)),
        ]),
      ),
    );
  }
}

// ── Empty state ────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final VoidCallback onNew;
  const _EmptyState({required this.onNew});

  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.people_outline, size: 60, color: Colors.grey),
      const SizedBox(height: 12),
      const Text('No buddies online.', style: TextStyle(fontSize: 16, color: Colors.grey)),
      const SizedBox(height: 16),
      ElevatedButton(
        onPressed: onNew,
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          textStyle: const TextStyle(fontSize: 15),
        ),
        child: const Text('Send Instant Message'),
      ),
    ]),
  );
}
