import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// VIOLET CYBERNET DESIGN SYSTEM
/// ─────────────────────────────────────────────────────────────────────────────
/// - Primary: Electric Neon Violet (#7C3AED / #8B5CF6 / #A855F7)
/// - Dark Base: Cybernet Obsidian (#080612 / #120E24 / #1B1437)
/// - Light Base: Cybernet Frost White (#F8F7FD / #FFFFFF / #F1EEFB)
/// - Shading Hierarchy: 100% -> 70% -> 50% -> 30%
/// ─────────────────────────────────────────────────────────────────────────────

class AppColors {
  // Brand Core Colors (Violet Cybernet)
  static const Color primary = Color(0xFF7C3AED); // Electric Violet
  static const Color primaryLight = Color(0xFF8B5CF6); // Neon Violet
  static const Color primaryGlow = Color(0xFFA855F7); // Violet Glow
  static const Color primaryDark = Color(0xFF581C87); // Deep Cyber Violet
  static const Color primaryContainer = Color(0xFF8B5CF6);
  static const Color onPrimary = Colors.white;

  static const Color tertiary = Color(0xFF06B6D4); // Cyber Cyan
  static const Color tertiaryContainer = Color(0xFF22D3EE);

  // Surface Tones - Dark Cybernet
  static const Color darkBackground = Color(0xFF080612); // Obsidian Abyss
  static const Color darkSurface = Color(0xFF120E24); // Cyber Card
  static const Color darkSurfaceElevated = Color(0xFF1C1538); // Elevated Panel
  static const Color darkBorder = Color(0x4D7C3AED); // Violet 30% border

  // Surface Tones - Light Cybernet
  static const Color lightBackground = Color(0xFFF8F7FD); // Frost White
  static const Color lightSurface = Color(0xFFFFFFFF); // Pure White
  static const Color lightSurfaceElevated = Color(0xFFF1EEFB); // Tinted Panel
  static const Color lightBorder = Color(0x337C3AED); // Violet 20% border

  // Default surfaces (mapped to light for backwards compatibility)
  static const Color surface = lightBackground;
  static const Color surfaceContainerLow = lightSurfaceElevated;
  static const Color surfaceContainerHighest = Color(0xFFE5E0F8);
  static const Color onSurface = Color(0xFF0F0B24); // Deep Obsidian Black
  static const Color onSurfaceVariant = Color(0xFF6B6684);
  static const Color error = Color(0xFFEF4444);
  static const Color outlineVariant = Color(0xFFDDD8F5);

  // Cyber Accents
  static const Color accentCyan = Color(0xFF06B6D4);
  static const Color accentPink = Color(0xFFEC4899);
  static const Color accentEmerald = Color(0xFF10B981);
  static const Color accentAmber = Color(0xFFF59E0B);
  static const Color accentBlue = Color(0xFF3B82F6);
  static const Color accentRose = Color(0xFFF43F5E);
  static const Color accentPurple = Color(0xFF9333EA);

  // ── 100 -> 70 -> 50 -> 30 Opacity / Shading Scale ──────────────────────────
  static const double op100 = 1.0;
  static const double op70 = 0.70;
  static const double op50 = 0.50;
  static const double op30 = 0.30;

  // Dark Mode Text Hierarchy
  static const Color darkText100 = Color(0xFFFFFFFF);
  static const Color darkText70 = Color(0xB3FFFFFF); // 70% white
  static const Color darkText50 = Color(0x80FFFFFF); // 50% white
  static const Color darkText30 = Color(0x4DFFFFFF); // 30% white

  // Light Mode Text Hierarchy
  static const Color lightText100 = Color(0xFF0F0B24); // 100% obsidian
  static const Color lightText70 = Color(0xB30F0B24); // 70% obsidian
  static const Color lightText50 = Color(0x800F0B24); // 50% obsidian
  static const Color lightText30 = Color(0x4D0F0B24); // 30% obsidian

  // ── Cyber Gradients ────────────────────────────────────────────────────────
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF6D28D9), Color(0xFF7C3AED), Color(0xFFA855F7)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient revenueGradient = LinearGradient(
    colors: [Color(0xFF1E0A3C), Color(0xFF4C1D95), Color(0xFF7C3AED)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient cyberVioletGradient = LinearGradient(
    colors: [Color(0xFF4C1D95), Color(0xFF7C3AED), Color(0xFF9333EA)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient purpleGradient = cyberVioletGradient;

  static const LinearGradient emeraldGradient = LinearGradient(
    colors: [Color(0xFF064E3B), Color(0xFF059669), Color(0xFF10B981)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient amberGradient = LinearGradient(
    colors: [Color(0xFF7C2D12), Color(0xFFD97706), Color(0xFFF59E0B)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

/// ─────────────────────────────────────────────────────────────────────────────
/// CYBERNET SHADOWS: 100 -> 70 -> 50 -> 30 SCALE
/// ─────────────────────────────────────────────────────────────────────────────
class CyberShadows {
  /// 100% Intensity - Hero Floating Cyber Glow
  static List<BoxShadow> shadow100(bool isDark) {
    return [
      BoxShadow(
        color: AppColors.primary.withValues(alpha: isDark ? 0.45 : 0.28),
        blurRadius: 24,
        spreadRadius: 0,
        offset: const Offset(0, 8),
      ),
      BoxShadow(
        color: AppColors.primaryGlow.withValues(alpha: isDark ? 0.25 : 0.15),
        blurRadius: 10,
        spreadRadius: -2,
        offset: const Offset(0, 2),
      ),
    ];
  }

  /// 70% Intensity - Prominent / Hover / Selected
  static List<BoxShadow> shadow70(bool isDark) {
    return [
      BoxShadow(
        color: isDark
            ? Colors.black.withValues(alpha: 0.70)
            : AppColors.primary.withValues(alpha: 0.18),
        blurRadius: 16,
        offset: const Offset(0, 6),
      ),
      BoxShadow(
        color: AppColors.primary.withValues(alpha: isDark ? 0.22 : 0.10),
        blurRadius: 8,
        offset: const Offset(0, 2),
      ),
    ];
  }

  /// 50% Intensity - Standard Card Elevation
  static List<BoxShadow> shadow50(bool isDark) {
    return [
      BoxShadow(
        color: isDark
            ? Colors.black.withValues(alpha: 0.50)
            : const Color(0xFF0F0B24).withValues(alpha: 0.08),
        blurRadius: 12,
        offset: const Offset(0, 4),
      ),
      BoxShadow(
        color: AppColors.primary.withValues(alpha: isDark ? 0.12 : 0.05),
        blurRadius: 4,
        offset: const Offset(0, 1),
      ),
    ];
  }

  /// 30% Intensity - Ambient Depth
  static List<BoxShadow> shadow30(bool isDark) {
    return [
      BoxShadow(
        color: isDark
            ? Colors.black.withValues(alpha: 0.30)
            : const Color(0xFF0F0B24).withValues(alpha: 0.04),
        blurRadius: 6,
        offset: const Offset(0, 2),
      ),
    ];
  }

  /// Convenience aliases for card and subtle shadows
  static List<BoxShadow> card(bool isDark) => shadow50(isDark);
  static List<BoxShadow> subtle(bool isDark) => shadow30(isDark);
}

/// ─────────────────────────────────────────────────────────────────────────────
/// APPLICATION THEMES
/// ─────────────────────────────────────────────────────────────────────────────
class AppTheme {
  // ── Light Theme: Cybernet Frost & Violet ────────────────────────────────────
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: Brightness.light,
        primary: AppColors.primary,
        primaryContainer: AppColors.primaryLight,
        secondary: AppColors.accentPink,
        tertiary: AppColors.accentCyan,
        surface: AppColors.lightSurface,
        onSurface: AppColors.lightText100,
        surfaceContainerLow: AppColors.lightSurfaceElevated,
        outline: AppColors.lightBorder,
        outlineVariant: AppColors.outlineVariant,
        error: AppColors.error,
      ),
      scaffoldBackgroundColor: AppColors.lightBackground,
      cardColor: AppColors.lightSurface,
      dividerColor: AppColors.primary.withValues(alpha: 0.12),
      textTheme: GoogleFonts.plusJakartaSansTextTheme().copyWith(
        displayLarge: GoogleFonts.plusJakartaSans(
          fontWeight: FontWeight.w800,
          color: AppColors.lightText100,
        ),
        headlineMedium: GoogleFonts.plusJakartaSans(
          fontWeight: FontWeight.w700,
          color: AppColors.lightText100,
        ),
        titleLarge: GoogleFonts.plusJakartaSans(
          fontWeight: FontWeight.w700,
          color: AppColors.lightText100,
        ),
        bodyLarge: GoogleFonts.inter(
          color: AppColors.lightText100,
        ),
        bodyMedium: GoogleFonts.inter(
          color: AppColors.lightText70,
        ),
        bodySmall: GoogleFonts.inter(
          color: AppColors.lightText50,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 2,
          shadowColor: AppColors.primary.withValues(alpha: 0.4),
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.lightSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: AppColors.primary.withValues(alpha: 0.15),
          ),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarIconBrightness: Brightness.dark,
        ),
        titleTextStyle: TextStyle(
          color: AppColors.primary,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        iconTheme: IconThemeData(color: AppColors.primary),
      ),
    );
  }

  // ── Dark Theme: Violet Cybernet Obsidian ────────────────────────────────────
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: Brightness.dark,
        primary: AppColors.primaryLight,
        primaryContainer: AppColors.primaryDark,
        secondary: AppColors.primaryGlow,
        tertiary: AppColors.accentCyan,
        surface: AppColors.darkSurface,
        onSurface: AppColors.darkText100,
        surfaceContainerLow: AppColors.darkSurfaceElevated,
        outline: AppColors.darkBorder,
        outlineVariant: const Color(0xFF2E2452),
        error: AppColors.error,
      ),
      scaffoldBackgroundColor: AppColors.darkBackground,
      cardColor: AppColors.darkSurface,
      dividerColor: AppColors.primary.withValues(alpha: 0.20),
      textTheme: GoogleFonts.plusJakartaSansTextTheme(
        ThemeData(brightness: Brightness.dark).textTheme,
      ).copyWith(
        displayLarge: GoogleFonts.plusJakartaSans(
          fontWeight: FontWeight.w800,
          color: AppColors.darkText100,
        ),
        headlineMedium: GoogleFonts.plusJakartaSans(
          fontWeight: FontWeight.w700,
          color: AppColors.darkText100,
        ),
        titleLarge: GoogleFonts.plusJakartaSans(
          fontWeight: FontWeight.w700,
          color: AppColors.darkText100,
        ),
        bodyLarge: GoogleFonts.inter(
          color: AppColors.darkText100,
        ),
        bodyMedium: GoogleFonts.inter(
          color: AppColors.darkText70,
        ),
        bodySmall: GoogleFonts.inter(
          color: AppColors.darkText50,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 4,
          shadowColor: AppColors.primary.withValues(alpha: 0.6),
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.darkSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: AppColors.primary.withValues(alpha: 0.25),
          ),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        iconTheme: IconThemeData(color: Colors.white),
      ),
    );
  }
}
