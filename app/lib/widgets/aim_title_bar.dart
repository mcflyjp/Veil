import 'package:flutter/material.dart';
import '../core/aim_theme.dart';

class AimTitleBar extends StatelessWidget {
  final String title;
  final bool isDark;
  final Widget? leading;
  final List<Widget>? actions;

  const AimTitleBar({
    super.key,
    required this.title,
    required this.isDark,
    this.leading,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [AimColors.darkSurface2, AimColors.darkBackground]
              : [AimColors.aimTitleBar, AimColors.aimTitleBarEnd],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            if (leading != null) leading!,
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontFamily: 'Arial',
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (actions != null) ...actions!,
          ],
        ),
      ),
    );
  }
}
