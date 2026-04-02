import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class BottomNavItem {
  final IconData icon;
  final IconData? activeIcon;
  final String? label;

  const BottomNavItem({
    required this.icon,
    this.activeIcon,
    this.label,
  });
}

class GlassBottomNavBar extends StatelessWidget {
  final int selectedIndex;
  final Function(int) onItemSelected;
  final List<BottomNavItem> items;
  final double height;

  const GlassBottomNavBar({
    super.key,
    required this.selectedIndex,
    required this.onItemSelected,
    required this.items,
    this.height = 65, // Strict Apple constant, but parameterized
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    final colors = Theme.of(context).extension<AppleKitColors>()!;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SafeArea(
      bottom: true,
      child: Padding(
        padding: const EdgeInsets.only(left: 24, right: 24, bottom: 12),
        child: SizedBox(
          height: height,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(height / 2),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                decoration: BoxDecoration(
                  color: colors.frostedGlassBackground,
                  borderRadius: BorderRadius.circular(height / 2),
                  border: Border.all(
                    color: colors.frostedGlassBorder,
                    width: 0.5,
                  ),
                  boxShadow: [
                     BoxShadow(
                      color: colors.glassShadowColor,
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    )
                  ]
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: List.generate(items.length, (index) {
                    final item = items[index];
                    final isSelected = index == selectedIndex;
                    
                    final targetIcon = isSelected 
                        ? (item.activeIcon ?? item.icon)
                        : item.icon;

                    return GestureDetector(
                      onTap: () => onItemSelected(index),
                      behavior: HitTestBehavior.opaque,
                      child: SizedBox( 
                        width: MediaQuery.of(context).size.width / (items.length + 1),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: Icon(
                            targetIcon,
                            key: ValueKey<IconData>(targetIcon),
                            color: isSelected 
                                ? (isDark ? Colors.white : Colors.black)
                                : (isDark ? Colors.white54 : Colors.black45),
                            size: isSelected ? 26 : 24,
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
