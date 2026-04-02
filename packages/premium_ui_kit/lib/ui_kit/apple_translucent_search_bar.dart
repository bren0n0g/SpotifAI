import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class AppleTranslucentSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String>? onSubmitted; // <-- Adicionamos o evento do Enter
  final Widget? suffixIcon; // <-- Adicionamos suporte ao ícone extra (Microfone)

  const AppleTranslucentSearchBar({
    super.key,
    required this.controller,
    required this.hintText,
    this.onSubmitted,
    this.suffixIcon,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          // Fundo de vidro genérico que funciona bem no claro e no escuro
          color: isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.05),
          child: TextField(
            controller: controller,
            onSubmitted: onSubmitted, // <-- Ligando o evento
            style: TextStyle(color: isDark ? Colors.white : Colors.black),
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600]),
              suffixIcon: suffixIcon, // <-- Ligando o ícone
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            ),
          ),
        ),
      ),
    );
  }
}