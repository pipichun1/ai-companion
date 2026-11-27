import 'package:flutter/material.dart';

import 'theme.dart';

/// 带主题的页面路由：过渡期间就用目标配色打底，
/// 避免那一帧露出 App 全局主题的底色（表现为"闪一下蓝"）。
Route<T> themedRoute<T>(
  Palette palette,
  Widget page, {
  Duration duration = const Duration(milliseconds: 200),
}) {
  final themed = Theme(data: buildTheme(palette), child: page);
  return PageRouteBuilder<T>(
    transitionDuration: duration,
    reverseTransitionDuration: const Duration(milliseconds: 150),
    pageBuilder: (context, animation, secondaryAnimation) => themed,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved =
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: ColoredBox(color: palette.bg, child: child),
      );
    },
  );
}
