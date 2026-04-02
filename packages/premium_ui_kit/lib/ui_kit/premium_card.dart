import 'package:flutter/material.dart';

class PremiumCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? color; // <-- Adicionamos a capacidade de receber cor
  final double? width;
  final double? height;

  const PremiumCard({
    super.key,
    required this.child,
    this.padding,
    this.color,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      padding: padding ?? const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        // Usa a cor que passamos na home_page, senão usa a do tema
        color: color ?? Theme.of(context).cardColor, 
        borderRadius: BorderRadius.circular(20), // Borda padrão Apple
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            spreadRadius: 0,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}