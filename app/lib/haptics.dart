import 'package:flutter/services.dart';

import 'prefs.dart';

/// 统一的震动反馈入口：受设置开关控制
class Haptics {
  Haptics._();

  static bool get _on => AppPrefs.instance.hapticsEnabled;

  /// 轻：复制、删除、保存成功、滑动返回
  static Future<void> light() async {
    if (!_on) return;
    try {
      await HapticFeedback.lightImpact();
    } catch (_) {}
  }

  /// 中：长按
  static Future<void> medium() async {
    if (!_on) return;
    try {
      await HapticFeedback.mediumImpact();
    } catch (_) {}
  }

  /// 重：删除确认这类不可逆操作
  static Future<void> heavy() async {
    if (!_on) return;
    try {
      await HapticFeedback.heavyImpact();
    } catch (_) {}
  }

  /// 选择感：切换配色、字体、开关
  static Future<void> select() async {
    if (!_on) return;
    try {
      await HapticFeedback.selectionClick();
    } catch (_) {}
  }

  /// 她的回复到达（可在设置里单独关掉）
  static Future<void> herMessage() async {
    if (!_on || !AppPrefs.instance.chatVibrate) return;
    try {
      await HapticFeedback.lightImpact();
    } catch (_) {}
  }
}
