import 'package:flutter/material.dart';

/// Единая тема приложения. Цветовая палитра выдержана в тёмных,
/// «пергаментно-магических» тонах, чтобы приложение не выглядело
/// как обычная стандартная форма, а создавало атмосферу D&D.
class AppTheme {
  static const Color background = Color(0xFF15171C);
  static const Color surface = Color(0xFF1E212A);
  static const Color surfaceVariant = Color(0xFF262A35);
  static const Color primary = Color(0xFFEA814C); // тёплый медно-красный
  static const Color accent = Color(0xFF7C9CBF); // холодный акцент (магия)
  static const Color danger = Color(0xFFC0453B);
  static const Color success = Color(0xFF5E9C6C);
  static const Color textPrimary = Color(0xFFEDE6DA);
  static const Color textSecondary = Color(0xFFA9A8A2);

  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: background,
      colorScheme: base.colorScheme.copyWith(
        primary: primary,
        secondary: accent,
        surface: surface,
        error: danger,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        elevation: 0,
        centerTitle: false,
        foregroundColor: textPrimary,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      textTheme: base.textTheme.apply(
        bodyColor: textPrimary,
        displayColor: textPrimary,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceVariant,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        ),
      ),
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: surface,
        selectedIconTheme: IconThemeData(color: primary),
        selectedLabelTextStyle: TextStyle(color: primary),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: primary,
        unselectedItemColor: textSecondary,
        type: BottomNavigationBarType.fixed,
      ),
      dividerColor: surfaceVariant,
    );
  }
}
