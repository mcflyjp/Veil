import 'package:flutter/material.dart';
import '../core/aim_theme.dart';

// LEGACY — sets a room-level m.room.message_retention state event with old
// timer options (30s/5m/1h/1d/1week). Superseded by the per-message,
// view-triggered disappearing timer added in v0.1.31 (see
// DisappearingMessageService and chat_screen.dart's _pickDisappearTimer /
// _pickEventDisappearTimer, which use the current 3s/5s/10s/1m options).
// Only reachable through chat_screen.dart's _setDisappearing(), which itself
// is wired to the chat title bar's timer icon but predates the redesign —
// review before relying on it; the per-message picker is the current path.

class DisappearingTimerDialog extends StatelessWidget {
  const DisappearingTimerDialog({super.key});

  @override
  Widget build(BuildContext context) {
    const options = [
      (label: 'Off', seconds: 0),
      (label: '30 seconds', seconds: 30),
      (label: '5 minutes', seconds: 300),
      (label: '1 hour', seconds: 3600),
      (label: '1 day', seconds: 86400),
      (label: '1 week', seconds: 604800),
    ];

    return AlertDialog(
      title: const Text('Disappearing Messages', style: TextStyle(fontFamily: 'Arial', fontSize: 13, fontWeight: FontWeight.bold)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Messages will automatically delete after:', style: TextStyle(fontFamily: 'Arial', fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 12),
          ...options.map((opt) => ListTile(
            dense: true,
            title: Text(opt.label, style: const TextStyle(fontFamily: 'Arial', fontSize: 12)),
            leading: Icon(opt.seconds == 0 ? Icons.timer_off : Icons.timer, size: 16, color: AimColors.aimBlue),
            onTap: () => Navigator.pop(context, opt.seconds),
          )),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      ],
    );
  }
}
