import 'package:flutter/material.dart';
import 'corely_theme.dart';

// Thème Corely — délègue entièrement au système de design Corely.
// Palette, typographie, composants : voir lib/app/corely_theme.dart.
abstract class AppTheme {
  static ThemeData get light => CorelyTokens.lightTheme;
  static ThemeData get dark  => CorelyTokens.darkTheme;
}
