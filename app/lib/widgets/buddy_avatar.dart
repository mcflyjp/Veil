import 'package:flutter/material.dart';
import '../core/aim_theme.dart';
import '../core/veil_theme.dart';

// Shared circular avatar used by the buddy list and hidden-chats screen.
// When tc.avatarRing is on (Modern, AIM Remastered) it wraps the flat circle
// in a conic-gradient ring — reusing the same per-letter gradient the avatar
// fill already uses, so ring and fill always read as one coherent color —
// plus a stronger presence-dot glow. Every other theme renders the same
// plain flat circle it always has; this widget changed nothing for them.
class BuddyAvatar extends StatelessWidget {
  final String initial;
  final VeilThemeColors tc;
  final bool isGroup; // groups don't get a presence dot — only DMs do
  final double size;

  const BuddyAvatar({
    super.key,
    required this.initial,
    required this.tc,
    this.isGroup = false,
    this.size = 46,
  });

  @override
  Widget build(BuildContext context) {
    final ringColors = VeilThemeColors.avatarGradientFor(initial);
    final circleSize = tc.avatarRing ? size - 4 : size;

    Widget circle = Container(
      width: circleSize, height: circleSize,
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
          style: TextStyle(color: tc.avatarText, fontSize: circleSize * 0.41,
              fontWeight: FontWeight.bold))),
    );

    if (tc.avatarRing) {
      circle = Container(
        width: size, height: size,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: SweepGradient(colors: [...ringColors, ringColors.first]),
        ),
        child: circle,
      );
    }

    final child = Stack(children: [
      circle,
      if (!isGroup)
        Positioned(bottom: 1, right: 1,
          child: Container(
            width: 12, height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AimColors.online,
              border: Border.all(color: tc.presenceBorder, width: 1.5),
              boxShadow: tc.avatarRing
                  ? [BoxShadow(color: AimColors.online.withAlpha(90), blurRadius: 5, spreadRadius: 1)]
                  : null,
            ),
          ),
        ),
    ]);

    return SizedBox(width: size, height: size, child: child);
  }
}
