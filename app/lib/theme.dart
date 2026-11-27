import 'package:flutter/material.dart';

/// 一套完整的配色：页面底色、面板、强调色、双方气泡
class Palette {
  const Palette({
    required this.id,
    required this.name,
    required this.brightness,
    required this.bg,
    required this.surface,
    required this.alt,
    required this.accent,
    required this.bubbleMine,
    required this.bubbleOther,
  });

  final String id;
  final String name;
  final Brightness brightness;
  final Color bg; // 页面底色
  final Color surface; // 顶栏 / 输入栏
  final Color alt; // 输入框、卡片
  final Color accent; // 强调色（按钮、气泡）
  final Color bubbleMine;
  final Color bubbleOther;

  bool get isLight => brightness == Brightness.light;

  /// 主文字色
  Color get fg => isLight ? const Color(0xFF1A1C1E) : Colors.white;

  /// 次要文字
  Color fgWith(double opacity) => fg.withValues(alpha: opacity);

  /// 图标/提示文字
  Color get hint => fgWith(isLight ? 0.45 : 0.35);

  /// 由用户自选的颜色推导出一整套
  factory Palette.custom({
    required Color bg,
    required Color accent,
    required Color bubbleMine,
    required Color bubbleOther,
  }) {
    final light = bg.computeLuminance() > 0.5;
    final fg = light ? const Color(0xFF1A1C1E) : Colors.white;
    return Palette(
      id: 'custom',
      name: '自定义',
      brightness: light ? Brightness.light : Brightness.dark,
      bg: bg,
      surface: Color.lerp(bg, fg, 0.06)!,
      alt: Color.lerp(bg, fg, 0.12)!,
      accent: accent,
      bubbleMine: bubbleMine,
      bubbleOther: bubbleOther,
    );
  }
}

const List<Palette> kPalettes = [
  Palette(
    id: 'midnight',
    name: '深海',
    brightness: Brightness.dark,
    bg: Color(0xFF0E1420),
    surface: Color(0xFF151C29),
    alt: Color(0xFF1C2534),
    accent: Color(0xFF3D7EFF),
    bubbleMine: Color(0xFF3D6FE0),
    bubbleOther: Color(0xFF222B3A),
  ),
  Palette(
    id: 'violet',
    name: '紫罗兰',
    brightness: Brightness.dark,
    bg: Color(0xFF141020),
    surface: Color(0xFF1B1630),
    alt: Color(0xFF241C3D),
    accent: Color(0xFF8B5CF6),
    bubbleMine: Color(0xFF7C4DFF),
    bubbleOther: Color(0xFF2A2340),
  ),
  Palette(
    id: 'sakura',
    name: '樱粉',
    brightness: Brightness.dark,
    bg: Color(0xFF1A1216),
    surface: Color(0xFF241A20),
    alt: Color(0xFF2E2029),
    accent: Color(0xFFF06292),
    bubbleMine: Color(0xFFD9538A),
    bubbleOther: Color(0xFF332630),
  ),
  Palette(
    id: 'forest',
    name: '森野',
    brightness: Brightness.dark,
    bg: Color(0xFF0F1714),
    surface: Color(0xFF16211D),
    alt: Color(0xFF1D2B26),
    accent: Color(0xFF3DBB8B),
    bubbleMine: Color(0xFF2E9E75),
    bubbleOther: Color(0xFF21302A),
  ),
  Palette(
    id: 'sunset',
    name: '落日',
    brightness: Brightness.dark,
    bg: Color(0xFF1A1310),
    surface: Color(0xFF241A15),
    alt: Color(0xFF2F221B),
    accent: Color(0xFFFF8A3D),
    bubbleMine: Color(0xFFE0712E),
    bubbleOther: Color(0xFF33251D),
  ),
  Palette(
    id: 'celadon',
    name: '青瓷',
    brightness: Brightness.dark,
    bg: Color(0xFF0F1618),
    surface: Color(0xFF162124),
    alt: Color(0xFF1D2A2E),
    accent: Color(0xFF4DD0C4),
    bubbleMine: Color(0xFF2FA79C),
    bubbleOther: Color(0xFF223034),
  ),
  Palette(
    id: 'graphite',
    name: '石墨',
    brightness: Brightness.dark,
    bg: Color(0xFF121314),
    surface: Color(0xFF1A1C1E),
    alt: Color(0xFF232629),
    accent: Color(0xFF8A94A6),
    bubbleMine: Color(0xFF546070),
    bubbleOther: Color(0xFF24272B),
  ),
  Palette(
    id: 'dawn',
    name: '晨光',
    brightness: Brightness.light,
    bg: Color(0xFFF4F6F9),
    surface: Color(0xFFFFFFFF),
    alt: Color(0xFFEDEFF3),
    accent: Color(0xFF4C9AFF),
    bubbleMine: Color(0xFF4C9AFF),
    bubbleOther: Color(0xFFFFFFFF),
  ),
];

Palette paletteById(String? id) {
  for (final p in kPalettes) {
    if (p.id == id) return p;
  }
  return kPalettes.first;
}

ThemeData buildTheme(Palette p) {
  final scheme = ColorScheme.fromSeed(
    seedColor: p.accent,
    brightness: p.brightness,
  ).copyWith(
    surface: p.surface,
    primary: p.accent,
  );
  return ThemeData(
    splashColor: p.accent.withValues(alpha: 0.12),
    highlightColor: p.accent.withValues(alpha: 0.08),
    hoverColor: p.accent.withValues(alpha: 0.06),
    useMaterial3: true,
    brightness: p.brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: p.bg,
    canvasColor: p.bg,
    appBarTheme: AppBarTheme(
      backgroundColor: p.surface,
      foregroundColor: p.fg,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    dividerColor: p.fgWith(0.08),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.alt,
      labelStyle: TextStyle(color: p.fgWith(0.5)),
      hintStyle: TextStyle(color: p.fgWith(0.3)),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: p.accent, width: 1.5),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: p.alt,
      contentTextStyle: TextStyle(color: p.fg),
    ),
  );
}
