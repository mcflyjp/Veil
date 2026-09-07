import 'package:flutter/material.dart';
import '../core/aim_theme.dart';

// UNUSED — not imported or referenced anywhere in the app. buddy_list_screen.dart
// draws its own presence dot inline (see _Avatar) instead of using this widget.
// Safe to delete unless a standalone presence dot is needed elsewhere later.

class PresenceDot extends StatelessWidget {
  final String? status;
  const PresenceDot({super.key, this.status});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'online' => AimColors.aimOnline,
      'unavailable' => AimColors.aimAway,
      _ => AimColors.aimOffline,
    };
    return Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1),
      ),
    );
  }
}
