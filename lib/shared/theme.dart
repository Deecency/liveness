import 'package:flutter/material.dart';

/// Visual theming for the liveness verification screen.
/// Layered on top of LivenessConfig's primary/success/error colors.
class LivenessTheme {
  final Color? backgroundColor;
  final Color surfaceColor;
  final Color titleColor;
  final Color mutedTextColor;
  final double cardRadius;
  final double ringSize;
  final double ringThickness;
  final Gradient? backgroundGradient;
  final bool glassmorphism;
  final String? fontFamily;
  final List<BoxShadow> cardShadow;

  const LivenessTheme({
    this.backgroundColor,
    this.surfaceColor = Colors.white,
    this.titleColor = const Color(0xFF111827),
    this.mutedTextColor = const Color(0xFF6B7280),
    this.cardRadius = 24,
    this.ringSize = 280,
    this.ringThickness = 6,
    this.backgroundGradient,
    this.glassmorphism = false,
    this.fontFamily,
    this.cardShadow = const [
      BoxShadow(
        color: Color(0x14000000),
        blurRadius: 28,
        offset: Offset(0, 10),
      ),
    ],
  });

  /// Ready-made dark theme
  static const LivenessTheme dark = LivenessTheme(
    backgroundColor: Color(0xFF0B0F1A),
    surfaceColor: Color(0xFF161B27),
    titleColor: Color(0xFFF3F4F6),
    mutedTextColor: Color(0xFF94A0B8),
    cardShadow: [
      BoxShadow(
        color: Color(0x40000000),
        blurRadius: 28,
        offset: Offset(0, 10),
      ),
    ],
  );

  /// Ready-made glassmorphism theme (best over a gradient/backgroundGradient)
  static LivenessTheme glass({Gradient? gradient}) => LivenessTheme(
    backgroundGradient:
        gradient ??
        const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
        ),
    surfaceColor: Colors.white.withValues(alpha: 0.14),
    titleColor: Colors.white,
    mutedTextColor: Colors.white70,
    glassmorphism: true,
    cardShadow: const [],
  );

  LivenessTheme copyWith({
    Color? backgroundColor,
    Color? surfaceColor,
    Color? titleColor,
    Color? mutedTextColor,
    double? cardRadius,
    double? ringSize,
    double? ringThickness,
    Gradient? backgroundGradient,
    bool? glassmorphism,
    String? fontFamily,
    List<BoxShadow>? cardShadow,
  }) {
    return LivenessTheme(
      backgroundColor: backgroundColor ?? this.backgroundColor,
      surfaceColor: surfaceColor ?? this.surfaceColor,
      titleColor: titleColor ?? this.titleColor,
      mutedTextColor: mutedTextColor ?? this.mutedTextColor,
      cardRadius: cardRadius ?? this.cardRadius,
      ringSize: ringSize ?? this.ringSize,
      ringThickness: ringThickness ?? this.ringThickness,
      backgroundGradient: backgroundGradient ?? this.backgroundGradient,
      glassmorphism: glassmorphism ?? this.glassmorphism,
      fontFamily: fontFamily ?? this.fontFamily,
      cardShadow: cardShadow ?? this.cardShadow,
    );
  }
}
