import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../core/client_manager.dart';
import '../core/aim_theme.dart';

class BuddyListScreen extends StatelessWidget {
  const BuddyListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final mgr = context.watch<ClientManager>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final rooms = mgr.rooms;
    final screenName = mgr.myScreenName;

    return Scaffold(
      body: Column(
        children: [
          // ── AIM-style title bar ──────────────────────────────────────
          _AimTitleBar(title: 'Buddy List', isDark: isDark, actions: [
            _TitleBarButton(icon: Icons.settings, tooltip: 'Settings', onTap: () => context.go('/buddylist/settings')),
          ]),

          // ── Screen name + status strip ───────────────────────────────
          Container(
            color: isDark ? AimColors.darkSectionBg : AimColors.titleBarStart,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(children: [
              _PresenceDot(online: true),
              const SizedBox(width: 6),
              Expanded(child: Text(screenName,
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis)),
              InkWell(
                onTap: () => context.go('/buddylist/new'),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.edit_note, color: Colors.white, size: 18),
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
                      ...rooms.map((r) => _BuddyRow(room: r, isDark: isDark)),
                    ]),
            ),
          ),

          // ── Bottom toolbar ──────────────────────────────────────────
          Container(
            height: 32,
            color: isDark ? const Color(0xFF111111) : AimColors.buddyListBg,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: isDark ? AimColors.darkBorder : AimColors.winBorder)),
            ),
            child: Row(children: [
              _ToolbarButton(icon: Icons.message, label: 'IM', onTap: () => context.go('/buddylist/new')),
              _ToolbarButton(icon: Icons.people, label: 'Chat', onTap: () => context.go('/buddylist/new')),
              const Spacer(),
              _ToolbarButton(icon: Icons.logout, label: 'Sign Off',
                  onTap: () => context.read<ClientManager>().logout()),
            ]),
          ),
        ],
      ),
    );
  }
}

class _AimTitleBar extends StatelessWidget {
  final String title;
  final bool isDark;
  final List<Widget> actions;
  const _AimTitleBar({required this.title, required this.isDark, this.actions = const []});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: isDark
            ? [AimColors.darkTitleBar, const Color(0xFF1A3A6A)]
            : [AimColors.titleBarStart, AimColors.titleBarEnd]),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(children: [
        const Icon(Icons.lock, color: Colors.white, size: 14),
        const SizedBox(width: 4),
        Expanded(child: Text('Veil — $title',
            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold))),
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
    child: Padding(padding: const EdgeInsets.all(4), child: Icon(icon, color: Colors.white, size: 14)),
  );
}

class _SectionHeader extends StatelessWidget {
  final String text;
  final bool isDark;
  const _SectionHeader(this.text, {required this.isDark});

  @override
  Widget build(BuildContext context) => Container(
    color: isDark ? AimColors.darkSectionBg : AimColors.sectionHeaderBg,
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    child: Row(children: [
      const Icon(Icons.arrow_drop_down, color: Colors.white, size: 16),
      Text(text, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
    ]),
  );
}

class _BuddyRow extends StatelessWidget {
  final Room room;
  final bool isDark;
  const _BuddyRow({required this.room, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final name = room.getLocalizedDisplayname();
    final last = room.lastEvent;
    final unread = room.notificationCount > 0;

    return InkWell(
      onTap: () => context.go('/buddylist/chat/${Uri.encodeComponent(room.id)}'),
      child: Container(
        color: isDark ? AimColors.darkBuddyBg : Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(
            color: isDark ? AimColors.darkBorder : const Color(0xFFDDDDDD), width: 0.5)),
        ),
        child: Row(children: [
          _PresenceDot(online: true),
          const SizedBox(width: 6),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(child: Text(name,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: unread ? FontWeight.bold : FontWeight.normal,
                    color: isDark ? AimColors.darkText : Colors.black,
                  ),
                  overflow: TextOverflow.ellipsis)),
                if (last != null)
                  Text(timeago.format(last.originServerTs, allowFromNow: true),
                    style: TextStyle(fontSize: 10, color: isDark ? Colors.grey[500] : Colors.grey[600])),
                if (unread) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: const Color(0xFF17369C),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('${room.notificationCount}',
                      style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                  ),
                ],
              ]),
              if (last != null)
                Text(last.body ?? '',
                  style: TextStyle(fontSize: 10,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                    fontWeight: unread ? FontWeight.bold : FontWeight.normal),
                  overflow: TextOverflow.ellipsis, maxLines: 1),
            ],
          )),
        ]),
      ),
    );
  }
}

class _PresenceDot extends StatelessWidget {
  final bool online;
  const _PresenceDot({required this.online});

  @override
  Widget build(BuildContext context) => Container(
    width: 8, height: 8,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: online ? AimColors.online : AimColors.offline,
      border: Border.all(color: Colors.white, width: 0.5),
    ),
  );
}

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
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: isDark ? Colors.grey[300] : Colors.black87),
          Text(label, style: TextStyle(fontSize: 8, color: isDark ? Colors.grey[300] : Colors.black87)),
        ]),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onNew;
  const _EmptyState({required this.onNew});

  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.people_outline, size: 40, color: Colors.grey),
      const SizedBox(height: 8),
      const Text('No buddies online.', style: TextStyle(fontSize: 12, color: Colors.grey)),
      const SizedBox(height: 12),
      ElevatedButton(onPressed: onNew, child: const Text('Send Instant Message')),
    ]),
  );
}
