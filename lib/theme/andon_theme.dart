import 'package:flutter/material.dart';

/// Colours sampled directly from the Andon radio cabinet, plus the surfaces
/// derived from them. Kept out of [ColorScheme] because these are material
/// finishes - wood and perforated metal - rather than semantic roles.
@immutable
class AndonPalette extends ThemeExtension<AndonPalette> {
  const AndonPalette({
    required this.walnutDark,
    required this.walnut,
    required this.walnutLight,
    required this.grille,
    required this.grillePerforation,
    required this.cabinetShadow,
  });

  final Color walnutDark; // #7C5940 - the frame, in shadow
  final Color walnut; // #9B7A65 - the top face
  final Color walnutLight; // #AD7E5C - the lit side
  final Color grille; // #ACACAC - perforated speaker cloth
  final Color grillePerforation;
  final Color cabinetShadow;

  static const light = AndonPalette(
    walnutDark: Color(0xFF7C5940),
    walnut: Color(0xFF9B7A65),
    walnutLight: Color(0xFFAD7E5C),
    grille: Color(0xFFC9C6C2),
    grillePerforation: Color(0x33463A31),
    cabinetShadow: Color(0x1A2B1D12),
  );

  /// After dark the cabinet reads as unlit wood: the same hues, much deeper,
  /// with the grille falling back to a dim graphite.
  static const dark = AndonPalette(
    walnutDark: Color(0xFF2A1D14),
    walnut: Color(0xFF3E2C20),
    walnutLight: Color(0xFF563D2B),
    grille: Color(0xFF3A3632),
    grillePerforation: Color(0x4D000000),
    cabinetShadow: Color(0x66000000),
  );

  @override
  AndonPalette copyWith({
    Color? walnutDark,
    Color? walnut,
    Color? walnutLight,
    Color? grille,
    Color? grillePerforation,
    Color? cabinetShadow,
  }) => AndonPalette(
    walnutDark: walnutDark ?? this.walnutDark,
    walnut: walnut ?? this.walnut,
    walnutLight: walnutLight ?? this.walnutLight,
    grille: grille ?? this.grille,
    grillePerforation: grillePerforation ?? this.grillePerforation,
    cabinetShadow: cabinetShadow ?? this.cabinetShadow,
  );

  @override
  AndonPalette lerp(AndonPalette? other, double t) {
    if (other == null) return this;
    return AndonPalette(
      walnutDark: Color.lerp(walnutDark, other.walnutDark, t)!,
      walnut: Color.lerp(walnut, other.walnut, t)!,
      walnutLight: Color.lerp(walnutLight, other.walnutLight, t)!,
      grille: Color.lerp(grille, other.grille, t)!,
      grillePerforation: Color.lerp(
        grillePerforation,
        other.grillePerforation,
        t,
      )!,
      cabinetShadow: Color.lerp(cabinetShadow, other.cabinetShadow, t)!,
    );
  }
}

/// The orange knob. Everything accent-coloured in the app traces back here.
const kAndonOrange = Color(0xFFDA6226);

class AndonTheme {
  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isLight = brightness == Brightness.light;

    var scheme = ColorScheme.fromSeed(
      seedColor: kAndonOrange,
      brightness: brightness,
    );

    // Warm the neutrals towards the wood. Material's generated greys are cool
    // by default, which fights the cabinet.
    scheme = isLight
        ? scheme.copyWith(
            surface: const Color(0xFFF6F1EC),
            surfaceContainerLowest: const Color(0xFFFFFBF8),
            surfaceContainerLow: const Color(0xFFF2EBE4),
            surfaceContainer: const Color(0xFFEDE4DC),
            surfaceContainerHigh: const Color(0xFFE7DCD3),
            surfaceContainerHighest: const Color(0xFFE1D5CA),
            outlineVariant: const Color(0xFFD5C7BA),
          )
        : scheme.copyWith(
            surface: const Color(0xFF17110D),
            surfaceContainerLowest: const Color(0xFF120D09),
            surfaceContainerLow: const Color(0xFF1E1712),
            surfaceContainer: const Color(0xFF241B15),
            surfaceContainerHigh: const Color(0xFF2E231B),
            surfaceContainerHighest: const Color(0xFF392C22),
            outlineVariant: const Color(0xFF4A3A2E),
          );

    final base = ThemeData(colorScheme: scheme, useMaterial3: true);

    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      extensions: [isLight ? AndonPalette.light : AndonPalette.dark],
      // Tight tracking on the large sizes, echoing the Andon FM wordmark.
      textTheme: base.textTheme.copyWith(
        displaySmall: base.textTheme.displaySmall?.copyWith(
          letterSpacing: -1.2,
          fontWeight: FontWeight.w500,
        ),
        headlineMedium: base.textTheme.headlineMedium?.copyWith(
          letterSpacing: -0.8,
          fontWeight: FontWeight.w500,
        ),
        headlineSmall: base.textTheme.headlineSmall?.copyWith(
          letterSpacing: -0.5,
          fontWeight: FontWeight.w500,
        ),
        titleLarge: base.textTheme.titleLarge?.copyWith(
          letterSpacing: -0.3,
          fontWeight: FontWeight.w600,
        ),
        labelLarge: base.textTheme.labelLarge?.copyWith(letterSpacing: 0.4),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        clipBehavior: Clip.antiAlias,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}
