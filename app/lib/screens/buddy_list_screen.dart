import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../core/client_manager.dart';
import '../core/aim_theme.dart';
import '../widgets/aim_title_bar.dart';
import '../widgets/presence_dot.dart';

class BuddyListScreen extends StatelessWidget {
  const BuddyListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final mgr = context.watch<ClientManager>();
    final displayName = mgr.myScreenName;
    final rooms = mgr.rooms;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight + 24),
        child: Column(
          children: [
            AimTitleBar(
              title: 'Veil — Buddy List',
              isDark: isDark,
              actions: [
                IconButton(icon: const Icon(Icons.settings, size: 14, color: Colors.white), onPressed: () => context.go('/buddylist/settings'), tooltip: 'Settings'),
              ],
            ),
            Container(
              height: kToolbarHeight,
              color: isDark ? AimColors.darkSurface2 : AimColors.aimBlue,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  const PresenceDot(status: 'online'),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      displayName,
                      style: const TextStyle(color: Colors.white, fontFamily: 'Arial', fontSize: 12, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_comment, size: 16, color: Colors.white),
                    onPressed: () => context.go('/buddylist/new'),
                    tooltip: 'New conversation',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: rooms.isEmpty
          ? _EmptyBuddyList(onNew: () => context.go('/buddylist/new'))
          : ListView(
              children: [
                _SectionHeader('Conversations (${rooms.length})'),
                ...rooms.map((room) => _BuddyTile(room: room, isDark: isDark)),
              ],
            ),
      floatingActionButton: FloatingActionButton.small(
        onPressed: () => context.go('/buddylist/new'),
        backgroundColor: AimColors.aimBlue,
        tooltip: 'New conversation',
        child: const Icon(Icons.add, color: Colors.white),
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

class _BuddyTile extends StatelessWidget {
  final Room room;
  final bool isDark;
  const _BuddyTile({required this.room, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final lastEvent = room.lastEvent;
    final unread = room.notificationCount > 0;
    final lastMessage = lastEvent?.body ?? '';
    final lastTime = lastEvent?.originServerTs;

    return InkWell(
      onTap: () => context.go('/buddylist/chat/${Uri.encodeComponent(room.id)}'),
      child: Container(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: isDark ? const Color(0xFF334466) : AimColors.aimBorder, width: 0.5)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: isDark ? AimColors.darkSurface2 : AimColors.aimLightBlue,
                  child: Text(
                    (room.getLocalizedDisplayname().isNotEmpty ? room.getLocalizedDisplayname()[0] : '?').toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontFamily: 'Arial', fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
                Positioned(
                  right: 0, bottom: 0,
                  child: PresenceDot(status: room.directChatMatrixID != null ? 'online' : null),
                ),
              ],
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          room.getLocalizedDisplayname(),
                          style: TextStyle(fontFamily: 'Arial', fontSize: 12, fontWeight: unread ? FontWeight.bold : FontWeight.normal),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (lastTime != null)
                        Text(
                          timeago.format(lastTime, allowFromNow: true),
                          style: const TextStyle(fontFamily: 'Arial', fontSize: 10, color: Colors.grey),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          lastMessage,
                          style: TextStyle(fontFamily: 'Arial', fontSize: 11, color: unread ? null : Colors.grey[600], fontWeight: unread ? FontWeight.bold : FontWeight.normal),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                      if (unread)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(color: AimColors.aimBlue, borderRadius: BorderRadius.circular(8)),
                          child: Text('${room.notificationCount}', style: const TextStyle(color: Colors.white, fontSize: 10, fontFamily: 'Arial')),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyBuddyList extends StatelessWidget {
  final VoidCallback onNew;
  const _EmptyBuddyList({required this.onNew});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.people_outline, size: 48, color: Colors.grey),
          const SizedBox(height: 12),
          const Text('Your buddy list is empty.', style: TextStyle(fontFamily: 'Arial', fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 4),
          const Text('Start a conversation to see people here.', style: TextStyle(fontFamily: 'Arial', fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: onNew, child: const Text('Send a Message')),
        ],
      ),
    );
  }
}
