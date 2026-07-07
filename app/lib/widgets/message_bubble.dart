import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../core/aim_theme.dart';

class MessageBubble extends StatelessWidget {
  final Event event;
  final bool isMe;
  final bool isDark;

  const MessageBubble({super.key, required this.event, required this.isMe, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final sender = event.senderFromMemoryOrFallback;
    final senderName = sender.displayName ?? event.senderId.split(':').first.replaceFirst('@', '');
    final time = timeago.format(event.originServerTs, allowFromNow: true);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            CircleAvatar(
              radius: 12,
              backgroundColor: isDark ? AimColors.darkSurface2 : AimColors.aimLightBlue,
              child: Text(
                senderName.isNotEmpty ? senderName[0].toUpperCase() : '?',
                style: const TextStyle(color: Colors.white, fontSize: 10, fontFamily: 'Arial', fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 6),
          ],
          Column(
            crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (!isMe)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2, left: 2),
                  child: Text(senderName, style: TextStyle(fontFamily: 'Arial', fontSize: 10, fontWeight: FontWeight.bold, color: isDark ? AimColors.aimLightBlue : AimColors.aimBlue)),
                ),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
                child: Container(
                  decoration: BoxDecoration(
                    color: isMe
                        ? (isDark ? AimColors.darkBubbleOut : AimColors.aimBubbleOut)
                        : (isDark ? AimColors.darkBubbleIn : AimColors.aimBubbleIn),
                    border: Border.all(color: isDark ? const Color(0xFF334466) : AimColors.aimBorder, width: 0.5),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(8),
                      topRight: const Radius.circular(8),
                      bottomLeft: isMe ? const Radius.circular(8) : const Radius.circular(2),
                      bottomRight: isMe ? const Radius.circular(2) : const Radius.circular(8),
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: _buildContent(context),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 2, left: 2, right: 2),
                child: Text(time, style: const TextStyle(fontFamily: 'Arial', fontSize: 9, color: Colors.grey)),
              ),
            ],
          ),
          if (isMe) const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (event.type == EventTypes.Encrypted) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline, size: 11, color: Colors.grey[500]),
          const SizedBox(width: 4),
          Text('Encrypted message', style: TextStyle(fontFamily: 'Arial', fontSize: 12, color: Colors.grey[500], fontStyle: FontStyle.italic)),
        ],
      );
    }

    switch (event.messageType) {
      case MessageTypes.Image:
        return _ImageContent(event: event);
      case MessageTypes.Video:
        return _MediaContent(event: event, icon: Icons.play_circle_outline, label: event.body);
      case MessageTypes.Audio:
        return _MediaContent(event: event, icon: Icons.audiotrack, label: event.body);
      case MessageTypes.File:
        return _MediaContent(event: event, icon: Icons.attach_file, label: event.body);
      default:
        return SelectableText(
          event.body,
          style: TextStyle(fontFamily: 'Arial', fontSize: 13, color: isDark ? const Color(0xFFE0E0E0) : const Color(0xFF111111)),
        );
    }
  }
}

class _ImageContent extends StatelessWidget {
  final Event event;
  const _ImageContent({required this.event});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uri?>(
      future: event.getAttachmentUri(),
      builder: (context, snap) {
        if (!snap.hasData || snap.data == null) return const SizedBox(width: 120, height: 80, child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
        return ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Image.network(snap.data!.toString(), width: 200, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 48, color: Colors.grey),
          ),
        );
      },
    );
  }
}

class _MediaContent extends StatelessWidget {
  final Event event;
  final IconData icon;
  final String label;
  const _MediaContent({required this.event, required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: AimColors.aimBlue),
        const SizedBox(width: 6),
        Flexible(child: Text(label, style: const TextStyle(fontFamily: 'Arial', fontSize: 12), overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}
