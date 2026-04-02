import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Extension designed to securely hold proprietary Apple aesthetic tokens 
/// not natively found in standard Material ThemeData representations.
class AppleKitColors extends ThemeExtension<AppleKitColors> {
  final Color frostedGlassBackground;
  final Color frostedGlassBorder;
  final Color frostedGlassText;
  final Color glassShadowColor;
  final Color premiumCardBackground;
  final Color premiumCardShadow;
  final Color softDivider;

  const AppleKitColors({
    required this.frostedGlassBackground,
    required this.frostedGlassBorder,
    required this.frostedGlassText,
    required this.glassShadowColor,
    required this.premiumCardBackground,
    required this.premiumCardShadow,
    required this.softDivider,
  });

  @override
  ThemeExtension<AppleKitColors> copyWith({
    Color? frostedGlassBackground,
    Color? frostedGlassBorder,
    Color? frostedGlassText,
    Color? glassShadowColor,
    Color? premiumCardBackground,
    Color? premiumCardShadow,
    Color? softDivider,
  }) {
    return AppleKitColors(
      frostedGlassBackground: frostedGlassBackground ?? this.frostedGlassBackground,
      frostedGlassBorder: frostedGlassBorder ?? this.frostedGlassBorder,
      frostedGlassText: frostedGlassText ?? this.frostedGlassText,
      glassShadowColor: glassShadowColor ?? this.glassShadowColor,
      premiumCardBackground: premiumCardBackground ?? this.premiumCardBackground,
      premiumCardShadow: premiumCardShadow ?? this.premiumCardShadow,
      softDivider: softDivider ?? this.softDivider,
    );
  }

  @override
  ThemeExtension<AppleKitColors> lerp(ThemeExtension<AppleKitColors>? other, double t) {
    if (other is! AppleKitColors) return this;
    return AppleKitColors(
      frostedGlassBackground: Color.lerp(frostedGlassBackground, other.frostedGlassBackground, t)!,
      frostedGlassBorder: Color.lerp(frostedGlassBorder, other.frostedGlassBorder, t)!,
      frostedGlassText: Color.lerp(frostedGlassText, other.frostedGlassText, t)!,
      glassShadowColor: Color.lerp(glassShadowColor, other.glassShadowColor, t)!,
      premiumCardBackground: Color.lerp(premiumCardBackground, other.premiumCardBackground, t)!,
      premiumCardShadow: Color.lerp(premiumCardShadow, other.premiumCardShadow, t)!,
      softDivider: Color.lerp(softDivider, other.softDivider, t)!,
    );
  }
}

class AppTheme {
  AppTheme._();

  static ThemeData get lightTheme {
    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: const Color(0xFFF2F2F7),
      textTheme: GoogleFonts.interTextTheme(ThemeData.light().textTheme),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
        },
      ),
      extensions: [
        AppleKitColors(
          frostedGlassBackground: Colors.white.withValues(alpha: 0.15),
          frostedGlassBorder: Colors.white.withValues(alpha: 0.5),
          frostedGlassText: Colors.black.withValues(alpha: 0.5),
          glassShadowColor: Colors.black.withValues(alpha: 0.05),
          premiumCardBackground: Colors.white,
          premiumCardShadow: Colors.black.withValues(alpha: 0.05),
          softDivider: Colors.black.withValues(alpha: 0.05),
        ),
      ]
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF000000),
      textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
       pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
        },
      ),
      extensions: [
        AppleKitColors(
          frostedGlassBackground: Colors.black.withValues(alpha: 0.25),
          frostedGlassBorder: Colors.white.withValues(alpha: 0.1),
          frostedGlassText: Colors.white.withValues(alpha: 0.6),
          glassShadowColor: Colors.black.withValues(alpha: 0.3),
          premiumCardBackground: const Color(0xFF1C1C1E),
          premiumCardShadow: Colors.black.withValues(alpha: 0.4),
          softDivider: Colors.white12,
        ),
      ]
    );
  }
}

// Global ValueNotifier for Theme Toggle to avoid taking on external State Management deps
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);
