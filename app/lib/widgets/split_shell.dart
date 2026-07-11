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

    // ── Narrow: BuddyListScreen always mounted; chat overlays on top.
    // Offstage keeps the go_router Navigator in the element tree at all times
    // so it is never destroyed between visits. Without this, the Navigator's
    // GlobalKey deactivation only persists for one frame — the user always
    // spends more than one frame on the buddy list, so the Navigator was being
    // disposed and remounted on every re-entry, causing a one-frame gray flash
    // (tc.scaffold = AIM Win98 gray #D4D0C8) before ChatScreen could paint.
    // With Offstage the Navigator is alive-but-hidden while at root, so go_router
    // pushes ChatScreen onto it in the background; by the time offstage flips to
    // false the screen is already fully rendered — first visible frame = full chat.
    return Material(
      color: tc.scaffold,
      child: Stack(children: [
        const BuddyListScreen(),
        Offstage(
          offstage: atRoot,
          child: Material(color: tc.scaffold, child: child),
        ),
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
