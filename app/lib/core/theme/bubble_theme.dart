import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class BubbleTheme {
  static const Color bgTop = Color(0xFF1A0F33);
  static const Color bgMid = Color(0xFF0A0D1C);
  static const Color bgBottom = Color(0xFF05070E);

  static const Color primaryViolet = Color(0xFF8C5CFF);
  static const Color accentMagenta = Color(0xFFC46BFF);
  static const Color liveEmerald = Color(0xFF34D399);
  static const Color dangerRed = Color(0xFFFF5A5F);

  static const Color glassFill = Color(0x14FFFFFF);
  static const Color glassBorder = Color(0x24FFFFFF);
  static const Color sheetSurface = Color(0xF0111322);

  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [bgTop, bgMid, bgBottom],
  );

  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryViolet, accentMagenta],
  );

  static ThemeData buildMaterialTheme() {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bgBottom,
      fontFamily: '.SF Pro Text',
      colorScheme: const ColorScheme.dark(
        primary: primaryViolet,
        secondary: accentMagenta,
        surface: sheetSurface,
        error: dangerRed,
      ),
      cupertinoOverrideTheme: const CupertinoThemeData(
        brightness: Brightness.dark,
        primaryColor: primaryViolet,
        scaffoldBackgroundColor: bgBottom,
      ),
      useMaterial3: true,
    );
  }
}
