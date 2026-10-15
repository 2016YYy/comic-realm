import 'package:flutter/material.dart';

/// 应用主题：Material 3 + Mihon / Kotatsu 风格的深色沉浸配色。
///
/// 只依赖一个种子色（用户可选），深浅两套由 [theme] 统一派生，
/// 避免各页面自己写死颜色导致观感不一致。
class AppTheme {
  AppTheme._();

  /// 可选的种子色（Mihon / Kotatsu 常用的一套）
  static const List<ThemeSeed> seeds = [
    ThemeSeed('靛紫', Color(0xFF6C5CE7)),
    ThemeSeed('深海蓝', Color(0xFF3B82F6)),
    ThemeSeed('青碧', Color(0xFF14B8A6)),
    ThemeSeed('森绿', Color(0xFF22C55E)),
    ThemeSeed('暖橙', Color(0xFFF97316)),
    ThemeSeed('绯红', Color(0xFFEF4444)),
    ThemeSeed('樱花粉', Color(0xFFEC4899)),
    ThemeSeed('石墨灰', Color(0xFF64748B)),
  ];

  /// 圆角与间距统一在这里定义
  static const double radiusCard = 14;
  static const double radiusLarge = 20;
  static const double gap = 12;

  static ThemeData theme(Brightness brightness, Color seed) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );

    // 深色下把表面色压深、去蓝调，贴近 Mihon 的纯暗背景观感
    final isDark = brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF111116) : scheme.surface;
    final surfaceContainer =
        isDark ? const Color(0xFF1A1A21) : scheme.surfaceContainerHigh;
    final surfaceContainerHigh =
        isDark ? const Color(0xFF23232C) : scheme.surfaceContainerHighest;

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme.copyWith(
        surface: surface,
        surfaceContainerLowest: isDark ? const Color(0xFF0B0B0F) : scheme.surfaceContainerLowest,
        surfaceContainerLow: isDark ? const Color(0xFF15151B) : scheme.surfaceContainerLow,
        surfaceContainer: surfaceContainer,
        surfaceContainerHigh: surfaceContainerHigh,
        surfaceContainerHighest:
            isDark ? const Color(0xFF2C2C37) : scheme.surfaceContainerHighest,
      ),
      scaffoldBackgroundColor: surface,
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        color: surfaceContainer,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusCard),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isDark ? const Color(0xFF0E0E13) : scheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 68,
        indicatorColor: scheme.primary.withValues(alpha: isDark ? 0.22 : 0.16),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w500,
          ),
        ),
      ),
      tabBarTheme: const TabBarThemeData(
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: Colors.transparent,
        labelStyle: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        unselectedLabelStyle: TextStyle(fontWeight: FontWeight.w500, fontSize: 15),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceContainer,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLarge),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(radiusLarge)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dividerTheme: DividerThemeData(
        color: isDark ? Colors.white10 : Colors.black12,
        thickness: 1,
        space: 1,
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
      ),
    );
  }
}

class ThemeSeed {
  final String label;
  final Color color;
  const ThemeSeed(this.label, this.color);
}
