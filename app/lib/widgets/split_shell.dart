import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../screens/buddy_list_screen.dart';
import '../core/aim_theme.dart';
import '../core/veil_user_prefs.dart';

/// Breakpoint above which the two-panel layout kicks in.
const double kSplitBreak = 700;

/// Adaptive shell: side-by-side on wide screens, full-screen stack on narrow.
class SplitShell extends StatelessWidget {
  final Widget child;
  final String matchedLocation;

  const SplitShell({super.key, required this.child, required this.matchedLocation});

  @override
  Widget build(BuildContext context) {
    final tc    = context.watch<VeilUserPrefs>().colors;
    final width = MediaQuery.of(context).size.width;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final atRoot = matchedLocation == '/buddylist';

    if (width >= kSplitBreak) {
      // ── Wide: buddy list (1/3) | chat (2/3) ──────────────────────────
      final listWidth = (width / 3).clamp(240.0, 380.0);
      return Scaffold(
        backgroundColor: tc.scaffold,
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

    // ── Narrow: always keep BuddyListScreen mounted, overlay child on top.
    // Using Stack bypasses go_router's page-transition Navigator completely,
    // which was causing the gray freeze when re-entering the same chat.
    return ColoredBox(
      color: tc.scaffold,
      child: Stack(children: [
        const BuddyListScreen(),
        if (!atRoot) Material(color: tc.scaffold, child: child),
      ]),
    );
  }
}

/// Right-panel placeholder shown when no conversation is open.
class SelectConversationPanel extends StatelessWidget {
  const SelectConversationPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final tc   = context.watch<VeilUserPrefs>().colors;
    final topPad = MediaQuery.of(context).padding.top;
    return Column(children: [
      Container(
        padding: EdgeInsets.fromLTRB(10, topPad + 12, 10, 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [tc.titleStart, tc.titleEnd]),
        ),
        child: Row(children: [
          Icon(Icons.lock, color: tc.titleOnColor.withAlpha(200), size: 20),
          const SizedBox(width: 6),
          Text('Veil — Instant Message',
              style: TextStyle(color: tc.titleOnColor, fontSize: 16,
                  fontWeight: FontWeight.bold)),
        ]),
      ),
      Expanded(
        child: Container(
          color: tc.chatBg,
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.chat_bubble_outline, size: 52, color: tc.timestampText),
              const SizedBox(height: 14),
              Text('Select a buddy to begin chatting',
                style: TextStyle(fontSize: 15, color: tc.previewText)),
            ]),
          ),
        ),
      ),
    ]);
  }
}
