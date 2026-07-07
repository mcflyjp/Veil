import 'package:flutter/material.dart';
import '../core/aim_theme.dart';

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
