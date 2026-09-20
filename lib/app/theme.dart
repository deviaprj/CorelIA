import 'package:flutter/material.dart';

/// Palette et tokens de design de CorelIA (source unique de vérité).
abstract class AppColors {
  static const primary = Color(0xFF003F5C); // Bleu foncé — headers, CTA
  static const accent = Color(0xFF58B4D1); // Bleu clair — bulles user
  static const chatBg = Color(0xFFF0F4F8); // Fond de l'écran de chat
  static const botBubble = Color(0xFFFFFFFF);
  static const userBubble = accent;
  static const onPrimary = Color(0xFFFFFFFF);
  static const onAccent = Color(0xFF003F5C);
  static const onSurface = Color(0xFF1A2E3B);
  static const onlineGreen = Color(0xFF22C55E);
  static const errorRed = Color(0xFFB00020);

  static const avatarGradient = LinearGradient(
    colors: [primary, accent],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const bubbleShadow = [
    BoxShadow(color: Color(0x1A000000), blurRadius: 8, offset: Offset(0, 2)),
  ];
  static const headerShadow = [
    BoxShadow(color: Color(0x14000000), blurRadius: 4, offset: Offset(0, 1)),
  ];

  static const bubbleRadius = 12.0;
  static const tailRadius = 4.0;
  static const inputRadius = 24.0;
  static const avatarSize = 36.0;
  static const maxChatWidth = 480.0;
}

/// Thèmes clair et sombre de l'application.
abstract class AppTheme {
  static ThemeData get light => ThemeData(
        useMaterial3: true,
        fontFamily: 'Inter',
        colorScheme: const ColorScheme(
          brightness: Brightness.light,
          primary: AppColors.primary,
          onPrimary: AppColors.onPrimary,
          primaryContainer: Color(0xFFCCE8F4),
          onPrimaryContainer: AppColors.primary,
          secondary: AppColors.accent,
          onSecondary: AppColors.onAccent,
          secondaryContainer: Color(0xFFDEF0F8),
          onSecondaryContainer: AppColors.primary,
          error: AppColors.errorRed,
          onError: AppColors.onPrimary,
          errorContainer: Color(0xFFFFDAD6),
          onErrorContainer: Color(0xFF410002),
          surface: AppColors.botBubble,
          onSurface: AppColors.onSurface,
          surfaceContainerHighest: Color(0xFFE8EEF4),
          onSurfaceVariant: Color(0xFF4A6375),
          outline: Color(0xFF8DAABB),
          outlineVariant: Color(0xFFCDD8E0),
        ),
        scaffoldBackgroundColor: AppColors.chatBg,
        appBarTheme: const AppBarTheme(
          elevation: 0,
          centerTitle: false,
          backgroundColor: AppColors.botBubble,
          foregroundColor: AppColors.primary,
          surfaceTintColor: Colors.transparent,
          titleTextStyle: TextStyle(
            fontFamily: 'Inter',
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.primary,
          ),
          iconTheme: IconThemeData(color: AppColors.primary),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFE8EEF4),
          hintStyle: const TextStyle(color: Color(0xFF8DAABB)),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppColors.inputRadius),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppColors.inputRadius),
            borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: AppColors.onSurface,
          contentTextStyle:
              const TextStyle(color: Colors.white, fontFamily: 'Inter'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        progressIndicatorTheme:
            const ProgressIndicatorThemeData(color: AppColors.primary),
      );

  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        fontFamily: 'Inter',
        colorScheme: const ColorScheme(
          brightness: Brightness.dark,
          primary: AppColors.accent,
          onPrimary: AppColors.primary,
          primaryContainer: Color(0xFF004B6A),
          onPrimaryContainer: Color(0xFFCCE8F4),
          secondary: Color(0xFF7ECDE8),
          onSecondary: Color(0xFF002F45),
          error: Color(0xFFCF6679),
          onError: Color(0xFF000000),
          surface: Color(0xFF0D1E28),
          onSurface: Color(0xFFDCECF5),
          surfaceContainerHighest: Color(0xFF1A2E3B),
          onSurfaceVariant: Color(0xFF8DAABB),
          outline: Color(0xFF4A6375),
          outlineVariant: Color(0xFF2A3D4A),
        ),
        scaffoldBackgroundColor: const Color(0xFF0A1820),
        appBarTheme: const AppBarTheme(
          elevation: 0,
          backgroundColor: Color(0xFF0D1E28),
          foregroundColor: Color(0xFFDCECF5),
          titleTextStyle: TextStyle(
            fontFamily: 'Inter',
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Color(0xFFDCECF5),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF1A2E3B),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppColors.inputRadius),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppColors.inputRadius),
            borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      );
}
