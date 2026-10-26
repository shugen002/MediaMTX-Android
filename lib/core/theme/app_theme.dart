import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Semantic colors that are not covered by [ColorScheme].
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.background,
    required this.surface,
    required this.surfaceHigh,
    required this.border,
    required this.textSecondary,
    required this.textTertiary,
    required this.success,
    required this.warning,
    required this.danger,
    required this.info,
    required this.accentSoft,
    required this.chartIn,
    required this.chartOut,
    required this.isDark,
  });

  final Color background;
  final Color surface;
  final Color surfaceHigh;
  final Color border;
  final Color textSecondary;
  final Color textTertiary;
  final Color success;
  final Color warning;
  final Color danger;
  final Color info;
  final Color accentSoft;
  final Color chartIn;
  final Color chartOut;
  final bool isDark;

  static const dark = AppColors(
    background: Color(0xFF080C12),
    surface: Color(0xFF111823),
    surfaceHigh: Color(0xFF182231),
    border: Color(0xFF253447),
    textSecondary: Color(0xFF93A4BA),
    textTertiary: Color(0xFF62738A),
    success: Color(0xFF35D6A4),
    warning: Color(0xFFFFB454),
    danger: Color(0xFFFF6377),
    info: Color(0xFF63A1FF),
    accentSoft: Color(0x1F5C92FF),
    chartIn: Color(0xFF5C92FF),
    chartOut: Color(0xFF35D6A4),
    isDark: true,
  );

  static const light = AppColors(
    background: Color(0xFFF4F7FB),
    surface: Color(0xFFFFFFFF),
    surfaceHigh: Color(0xFFF8FAFE),
    border: Color(0xFFE1E8F2),
    textSecondary: Color(0xFF607086),
    textTertiary: Color(0xFF8D9CB0),
    success: Color(0xFF0BAA7C),
    warning: Color(0xFFD98213),
    danger: Color(0xFFE04458),
    info: Color(0xFF2563EB),
    accentSoft: Color(0xFFE8F0FF),
    chartIn: Color(0xFF2563EB),
    chartOut: Color(0xFF0BAA7C),
    isDark: false,
  );

  @override
  AppColors copyWith({
    Color? background,
    Color? surface,
    Color? surfaceHigh,
    Color? border,
    Color? textSecondary,
    Color? textTertiary,
    Color? success,
    Color? warning,
    Color? danger,
    Color? info,
    Color? accentSoft,
    Color? chartIn,
    Color? chartOut,
    bool? isDark,
  }) {
    return AppColors(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceHigh: surfaceHigh ?? this.surfaceHigh,
      border: border ?? this.border,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      info: info ?? this.info,
      accentSoft: accentSoft ?? this.accentSoft,
      chartIn: chartIn ?? this.chartIn,
      chartOut: chartOut ?? this.chartOut,
      isDark: isDark ?? this.isDark,
    );
  }

  @override
  AppColors lerp(covariant AppColors? other, double t) {
    if (other == null) return this;
    return AppColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceHigh: Color.lerp(surfaceHigh, other.surfaceHigh, t)!,
      border: Color.lerp(border, other.border, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      info: Color.lerp(info, other.info, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      chartIn: Color.lerp(chartIn, other.chartIn, t)!,
      chartOut: Color.lerp(chartOut, other.chartOut, t)!,
      isDark: t < 0.5 ? isDark : other.isDark,
    );
  }
}

extension AppColorsContext on BuildContext {
  AppColors get colors =>
      Theme.of(this).extension<AppColors>() ?? AppColors.dark;
}

class AppTheme {
  static const _brand = Color(0xFF5C92FF);
  static const _aqua = Color(0xFF35D6A4);
  static const _fontFallback = <String>[
    'Noto Sans SC',
    'Noto Sans CJK SC',
    'PingFang SC',
  ];

  static ThemeData get dark => _build(
    brightness: Brightness.dark,
    colors: AppColors.dark,
    scheme: const ColorScheme.dark(
      primary: _brand,
      onPrimary: Color(0xFF04101F),
      secondary: _aqua,
      onSecondary: Color(0xFF002117),
      tertiary: Color(0xFFFFB454),
      error: Color(0xFFFF6377),
      onError: Color(0xFF2B0006),
      surface: Color(0xFF111823),
      onSurface: Color(0xFFF1F6FE),
      outline: Color(0xFF253447),
    ),
  );

  static ThemeData get light => _build(
    brightness: Brightness.light,
    colors: AppColors.light,
    scheme: const ColorScheme.light(
      primary: _brand,
      onPrimary: Colors.white,
      secondary: _aqua,
      onSecondary: Color(0xFF002117),
      tertiary: Color(0xFFD98213),
      error: Color(0xFFE04458),
      onError: Colors.white,
      surface: Colors.white,
      onSurface: Color(0xFF101827),
      outline: Color(0xFFE1E8F2),
    ),
  );

  static ThemeData _build({
    required Brightness brightness,
    required AppColors colors,
    required ColorScheme scheme,
  }) {
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: colors.background,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
    );

    TextStyle text(
      double size,
      FontWeight weight, {
      double? height,
      double spacing = 0,
      Color? color,
    }) {
      return TextStyle(
        fontSize: size,
        fontWeight: weight,
        height: height,
        letterSpacing: spacing,
        color: color ?? scheme.onSurface,
        fontFamilyFallback: _fontFallback,
        fontFeatures: const [FontFeature.tabularFigures()],
      );
    }

    final textTheme = TextTheme(
      displayLarge: text(40, FontWeight.w700, height: 1.05, spacing: -1.4),
      displayMedium: text(32, FontWeight.w700, height: 1.08, spacing: -1.0),
      headlineLarge: text(26, FontWeight.w700, height: 1.15, spacing: -0.6),
      headlineMedium: text(22, FontWeight.w700, height: 1.2, spacing: -0.4),
      headlineSmall: text(19, FontWeight.w600, height: 1.25, spacing: -0.2),
      titleLarge: text(17, FontWeight.w600, height: 1.3),
      titleMedium: text(15, FontWeight.w600, height: 1.35),
      titleSmall: text(13, FontWeight.w600, height: 1.35),
      bodyLarge: text(15, FontWeight.w400, height: 1.55),
      bodyMedium: text(14, FontWeight.w400, height: 1.55),
      bodySmall: text(12.5, FontWeight.w400, height: 1.45),
      labelLarge: text(14, FontWeight.w600, height: 1.25),
      labelMedium: text(12, FontWeight.w600, height: 1.25, spacing: 0.2),
      labelSmall: text(10.5, FontWeight.w700, height: 1.2, spacing: 0.5),
    );

    return base.copyWith(
      extensions: [colors],
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      dividerColor: colors.border,
      dividerTheme: DividerThemeData(
        color: colors.border,
        thickness: 1,
        space: 1,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: colors.background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
        systemOverlayStyle: brightness == Brightness.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
      ),
      cardTheme: CardThemeData(
        color: colors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: colors.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surfaceHigh,
        hintStyle: textTheme.bodyMedium?.copyWith(color: colors.textTertiary),
        labelStyle: textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colors.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colors.danger, width: 1.5),
        ),
        errorStyle: textTheme.bodySmall?.copyWith(color: colors.danger),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          minimumSize: const Size(64, 50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: textTheme.labelLarge,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.onSurface,
          minimumSize: const Size(64, 48),
          side: BorderSide(color: colors.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          textStyle: textTheme.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      iconTheme: IconThemeData(color: colors.textSecondary, size: 22),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        backgroundColor: Colors.transparent,
        elevation: 0,
        indicatorColor: Colors.transparent,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return textTheme.labelSmall?.copyWith(
            color: selected ? scheme.primary : colors.textTertiary,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 23,
            color: selected ? scheme.primary : colors.textTertiary,
          );
        }),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: scheme.primary,
        unselectedLabelColor: colors.textSecondary,
        indicatorColor: scheme.primary,
        dividerColor: Colors.transparent,
        labelStyle: textTheme.labelLarge,
        unselectedLabelStyle: textTheme.labelLarge,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colors.surfaceHigh,
        side: BorderSide(color: colors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        labelStyle: textTheme.labelMedium?.copyWith(
          color: colors.textSecondary,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colors.surfaceHigh,
        contentTextStyle: textTheme.bodyMedium,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: colors.border),
        ),
        elevation: 8,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: textTheme.headlineSmall,
        contentTextStyle: textTheme.bodyMedium,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: colors.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        showDragHandle: true,
        dragHandleColor: colors.border,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.onPrimary
              : colors.textTertiary,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.primary
              : colors.surfaceHigh,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.primary
              : colors.border,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.primary
              : Colors.transparent,
        ),
        side: BorderSide(color: colors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: colors.surfaceHigh,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: colors.surfaceHigh,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.border),
        ),
        textStyle: textTheme.bodySmall,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: colors.textSecondary,
        textColor: scheme.onSurface,
        subtitleTextStyle: textTheme.bodySmall?.copyWith(
          color: colors.textSecondary,
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.iOS: ZoomPageTransitionsBuilder(),
        },
      ),
    );
  }
}
