import 'package:flutter/material.dart';
import '../screens/buddy_list_screen.dart';
import '../core/aim_theme.dart';

/// Breakpoint above which the two-panel layout kicks in.
const double kSplitBreak = 700;

/// Adaptive shell: side-by-side on wide screens, full-screen stack on narrow.
class SplitShell extends StatelessWidget {
  final bool atRoot;
  final Widget child;

  const SplitShell({super.key, required this.atRoot, required this.child});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (width >= kSplitBreak) {
      // ── Wide: buddy list (1/3) | chat (2/3) ──────────────────────────
      final listWidth = (width / 3).clamp(240.0, 380.0);
      return Scaffold(
        body: Row(children: [
          SizedBox(width: listWidth, child: const BuddyListScreen()),
          Container(
            width: 1,
            color: isDark ? AimColors.darkBorder : AimColors.winBorder,
          ),
          Expanded(child: child),
        ]),
      );
    }

    // ── Narrow: buddy list full-screen at root, child otherwise ──────────
    if (atRoot) {
      return const Scaffold(body: BuddyListScreen());
    }
    return child; // ChatScreen / SettingsScreen / NewChatScreen each have Scaffold
  }
}

/// Right-panel placeholder shown when no conversation is open.
class SelectConversationPanel extends StatelessWidget {
  const SelectConversationPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(children: [
      // AIM-style title bar
      Container(
        height: 48,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: isDark
              ? [AimColors.darkTitleBar, const Color(0xFF1A3A6A)]
              : [AimColors.titleBarStart, AimColors.titleBarEnd]),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: const Row(children: [
          Icon(Icons.lock, color: Colors.white, size: 20),
          SizedBox(width: 6),
          Text('Veil — Instant Message',
              style: TextStyle(color: Colors.white, fontSize: 16,
                  fontWeight: FontWeight.bold)),
        ]),
      ),
      // Empty state
      Expanded(
        child: Container(
          color: isDark ? AimColors.darkChatBg : AimColors.chatBg,
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.chat_bubble_outline, size: 52,
                  color: isDark ? Colors.grey[700] : Colors.grey[400]),
              const SizedBox(height: 14),
              Text('Select a buddy to begin chatting',
                style: TextStyle(fontSize: 15,
                    color: isDark ? Colors.grey[600] : Colors.grey[500])),
            ]),
          ),
        ),
      ),
    ]);
  }
}
