import 'package:flutter/material.dart';
import 'cofely_theme.dart';

// Thème Corely — délègue entièrement au système de design Cofely.
// Palette, typographie, composants : voir lib/app/cofely_theme.dart.
abstract class AppTheme {
  static ThemeData get light => CofelyTokens.lightTheme;
  static ThemeData get dark  => CofelyTokens.darkTheme;
}
