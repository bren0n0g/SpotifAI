import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class ThemeToggleButton extends StatelessWidget {
  final bool isDark;
  final VoidCallback onToggle;

  const ThemeToggleButton({
    super.key,
    required this.isDark,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        transitionBuilder: (child, animation) => RotationTransition(
          turns: animation,
          child: FadeTransition(opacity: animation, child: child),
        ),
        child: Icon(
          isDark ? CupertinoIcons.sun_max : CupertinoIcons.moon,
          key: ValueKey<bool>(isDark),
          color: isDark ? Colors.white : Colors.black87,
        ),
      ),
      onPressed: onToggle,
    );
  }
}
