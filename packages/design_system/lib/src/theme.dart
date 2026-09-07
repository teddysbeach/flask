import 'package:flutter/material.dart';

import 'tokens/tokens.g.dart';

/// 팔레트를 위젯 트리에 흘려보낸다.
///
/// `Theme.of(context).colorScheme` 만으로는 부족하다 — SEED 토큰에는 Material 이
/// 이름을 갖고 있지 않은 것들(surfaceSunken, textTertiary, ink*)이 있고,
/// 그것들이 학습지 HTML 과 같은 값이어야 앱과 학습지가 한 몸으로 보인다.
@immutable
class DsTheme extends ThemeExtension<DsTheme> {
  const DsTheme({required this.palette});

  final DsPalette palette;

  static DsPalette of(BuildContext context) =>
      Theme.of(context).extension<DsTheme>()?.palette ?? DsPalette.light;

  @override
  DsTheme copyWith({DsPalette? palette}) => DsTheme(palette: palette ?? this.palette);

  /// 팔레트는 통째로 바뀌는 값이라 중간 보간을 하지 않는다.
  /// 색을 하나씩 섞으면 라이트/다크 전환 중간에 대비가 무너지는 구간이 생긴다.
  @override
  DsTheme lerp(ThemeExtension<DsTheme>? other, double t) =>
      t < 0.5 ? this : (other as DsTheme? ?? this);
}

TextStyle dsTextStyle(DsTypeStyle s, Color color) => TextStyle(
      fontFamily: DsFont.family,
      fontFamilyFallback: DsFont.sans,
      fontSize: s.size,
      height: s.lineHeight,
      fontWeight: FontWeight.values[(s.weight ~/ 100) - 1],
      letterSpacing: s.letterSpacing,
      color: color,
    );

ThemeData dsThemeData(Brightness brightness) {
  final p = brightness == Brightness.dark ? DsPalette.dark : DsPalette.light;

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    scaffoldBackgroundColor: p.surfaceBase,
    fontFamily: DsFont.family,
    fontFamilyFallback: DsFont.sans,
    extensions: [DsTheme(palette: p)],
    colorScheme: ColorScheme(
      brightness: brightness,
      primary: p.brandPrimary,
      onPrimary: p.brandOnPrimary,
      primaryContainer: p.brandPrimarySubtle,
      onPrimaryContainer: p.brandTextOnSubtle,
      secondary: p.neutralPrimaryBase,
      onSecondary: p.neutralPrimaryOnBase,
      error: p.statusDanger,
      onError: p.textInverted,
      errorContainer: p.statusBgDanger,
      onErrorContainer: p.statusDanger,
      surface: p.surfaceRaised,
      onSurface: p.textPrimary,
      surfaceContainerLowest: p.surfaceRaised,
      surfaceContainerLow: p.surfaceSunken,
      surfaceContainer: p.surfaceSunken,
      outline: p.borderStrong,
      outlineVariant: p.borderSubtle,
    ),
    textTheme: TextTheme(
      displayLarge: dsTextStyle(DsType.display, p.textPrimary),
      headlineLarge: dsTextStyle(DsType.h1, p.textPrimary),
      headlineMedium: dsTextStyle(DsType.h2, p.textPrimary),
      titleLarge: dsTextStyle(DsType.h3, p.textPrimary),
      bodyLarge: dsTextStyle(DsType.bodyLg, p.textPrimary),
      bodyMedium: dsTextStyle(DsType.body, p.textPrimary),
      bodySmall: dsTextStyle(DsType.caption, p.textSecondary),
      labelLarge: dsTextStyle(DsType.bodyLg, p.textPrimary),
    ),
    dividerTheme: DividerThemeData(color: p.borderSubtle, thickness: DsWorksheet.ruleWidth, space: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: p.surfaceBase,
      surfaceTintColor: Colors.transparent,
      foregroundColor: p.textPrimary,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: dsTextStyle(DsType.h3, p.textPrimary),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.brandPrimary,
        foregroundColor: p.brandOnPrimary,
        disabledBackgroundColor: p.textDisabled,
        disabledForegroundColor: p.textInverted,
        // 접근성: 터치 영역은 최소 48dp. 디자인이 작아 보여도 여기서 줄이지 않는다.
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DsRadius.md)),
        textStyle: dsTextStyle(DsType.bodyLg, p.brandOnPrimary).copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.textPrimary,
        side: BorderSide(color: p.borderSubtle),
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DsRadius.md)),
        textStyle: dsTextStyle(DsType.bodyLg, p.textPrimary).copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: p.brandText,
        minimumSize: const Size(48, 48),
        textStyle: dsTextStyle(DsType.body, p.brandText).copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.surfaceRaised,
      hintStyle: dsTextStyle(DsType.bodyLg, p.textPlaceholder),
      contentPadding: EdgeInsets.symmetric(horizontal: DsSpace.s4, vertical: DsSpace.s4),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(DsRadius.md),
        borderSide: BorderSide(color: p.borderSubtle),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(DsRadius.md),
        borderSide: BorderSide(color: p.borderSubtle),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(DsRadius.md),
        borderSide: BorderSide(color: p.borderFocus, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(DsRadius.md),
        borderSide: BorderSide(color: p.statusDanger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(DsRadius.md),
        borderSide: BorderSide(color: p.statusDanger, width: 2),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: p.neutralPrimaryBase,
      contentTextStyle: dsTextStyle(DsType.body, p.neutralPrimaryOnBase),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DsRadius.md)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.surfaceOverlay,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(DsRadius.lg)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.surfaceOverlay,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DsRadius.lg)),
    ),
  );
}
