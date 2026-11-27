import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme.dart';

/// 全局个性化设置
class AppPrefs extends ChangeNotifier {
  AppPrefs._();

  static final AppPrefs instance = AppPrefs._();

  String? avatarPath; // 她的头像
  String? myAvatarPath; // 我的头像
  String? chatBgPath; // 聊天背景
  String? homeBgPath; // 消息列表背景
  String paletteId = 'midnight';
  String? homePaletteId;
  bool hapticsEnabled = true;
  bool chatVibrate = true;
  double bubbleOpacity = 0.95;
  double bgOpacity = 0.45;
  int fontScaleIdx = 1; // 0小 1中 2大
  bool glassComposer = false;
  bool selfDress = true;
  double glassSigma = 22; // 输入栏毛玻璃
  int customBg = 0xFF0E1420;
  int customAccent = 0xFF3D7EFF;
  int customMine = 0xFF3D6FE0;
  int customOther = 0xFF222B3A;

  bool _loaded = false;
  bool get loaded => _loaded;

  /// 当前生效的调色板
  Palette get palette {
    if (paletteId == 'custom') {
      return Palette.custom(
        bg: Color(customBg),
        accent: Color(customAccent),
        bubbleMine: Color(customMine),
        bubbleOther: Color(customOther),
      );
    }
    return paletteById(paletteId);
  }

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    avatarPath = p.getString('ui_avatar');
    myAvatarPath = p.getString('ui_my_avatar');
    chatBgPath = p.getString('ui_bg');
    homeBgPath = p.getString('ui_home_bg');
    paletteId = p.getString('ui_palette') ?? 'midnight';
    homePaletteId = p.getString('ui_home_palette');
    hapticsEnabled = p.getBool('ui_haptics') ?? true;
    chatVibrate = p.getBool('ui_chat_vibrate') ?? true;
    bubbleOpacity = p.getDouble('ui_bubble_opacity') ?? 0.95;
    selfDress = p.getBool('ui_self_dress') ?? true;
    bgOpacity = p.getDouble('ui_bg_opacity') ?? 0.45;
    fontScaleIdx = p.getInt('ui_font_scale') ?? 1;
    glassComposer = p.getBool('ui_glass_composer') ?? false;
    glassSigma = p.getDouble('ui_glass_sigma') ?? 22;
    customBg = p.getInt('ui_custom_bg') ?? 0xFF0E1420;
    customAccent = p.getInt('ui_custom_accent') ?? 0xFF3D7EFF;
    customMine = p.getInt('ui_custom_mine') ?? 0xFF3D6FE0;
    customOther = p.getInt('ui_custom_other') ?? 0xFF222B3A;
    _loaded = true;
    notifyListeners();
  }

  Future<void> _setStr(String key, String? value, void Function() apply) async {
    apply();
    final p = await SharedPreferences.getInstance();
    if (value == null) {
      await p.remove(key);
    } else {
      await p.setString(key, value);
    }
    notifyListeners();
  }

  Future<void> _setInt(String key, int value, void Function() apply) async {
    apply();
    final p = await SharedPreferences.getInstance();
    await p.setInt(key, value);
    notifyListeners();
  }

  Future<void> setAvatar(String? path) =>
      _setStr('ui_avatar', path, () => avatarPath = path);

  Future<void> setMyAvatar(String? path) =>
      _setStr('ui_my_avatar', path, () => myAvatarPath = path);

  Future<void> setChatBg(String? path) =>
      _setStr('ui_bg', path, () => chatBgPath = path);

  Future<void> setHomeBg(String? path) =>
      _setStr('ui_home_bg', path, () => homeBgPath = path);

  Future<void> setPalette(String id) async {
    paletteId = id;
    final p = await SharedPreferences.getInstance();
    await p.setString('ui_palette', id);
    notifyListeners();
  }

  /// 主页独立配色；null 表示跟随全局
  Palette get homePalette =>
      homePaletteId == null ? palette : paletteById(homePaletteId);

  Future<void> setSelfDress(bool v) async {
    selfDress = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool('ui_self_dress', v);
    notifyListeners();
  }

  Future<void> setHapticsEnabled(bool v) async {
    hapticsEnabled = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool('ui_haptics', v);
    notifyListeners();
  }

  Future<void> setChatVibrate(bool v) async {
    chatVibrate = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool('ui_chat_vibrate', v);
    notifyListeners();
  }

  Future<void> setHomePalette(String? id) async {
    homePaletteId = (id == 'global') ? null : id;
    final p = await SharedPreferences.getInstance();
    if (homePaletteId == null) {
      await p.remove('ui_home_palette');
    } else {
      await p.setString('ui_home_palette', homePaletteId!);
    }
    notifyListeners();
  }

  Future<void> setBubbleOpacity(double value) async {
    bubbleOpacity = value.clamp(0.2, 1.0);
    final p = await SharedPreferences.getInstance();
    await p.setDouble('ui_bubble_opacity', bubbleOpacity);
    notifyListeners();
  }

  double get fontScale => const [0.9, 1.0, 1.15][fontScaleIdx.clamp(0, 2)];

  Future<void> setFontScaleIdx(int idx) async {
    fontScaleIdx = idx.clamp(0, 2);
    final p = await SharedPreferences.getInstance();
    await p.setInt('ui_font_scale', fontScaleIdx);
    notifyListeners();
  }

  Future<void> setGlassSigma(double value) async {
    glassSigma = value.clamp(0.0, 40.0);
    final p = await SharedPreferences.getInstance();
    await p.setDouble('ui_glass_sigma', glassSigma);
    notifyListeners();
  }

  Future<void> setGlassComposer(bool value) async {
    glassComposer = value;
    final p = await SharedPreferences.getInstance();
    await p.setBool('ui_glass_composer', value);
    notifyListeners();
  }

  Future<void> setBgOpacity(double value) async {
    bgOpacity = value.clamp(0.0, 1.0);
    final p = await SharedPreferences.getInstance();
    await p.setDouble('ui_bg_opacity', bgOpacity);
    notifyListeners();
  }

  Future<void> setCustomBg(int c) =>
      _setInt('ui_custom_bg', c, () => customBg = c);

  Future<void> setCustomAccent(int c) =>
      _setInt('ui_custom_accent', c, () => customAccent = c);

  Future<void> setCustomMine(int c) =>
      _setInt('ui_custom_mine', c, () => customMine = c);

  Future<void> setCustomOther(int c) =>
      _setInt('ui_custom_other', c, () => customOther = c);

  File? _file(String? path) {
    if (path == null) return null;
    final f = File(path);
    return f.existsSync() ? f : null;
  }

  File? get avatarFile => _file(avatarPath);
  File? get myAvatarFile => _file(myAvatarPath);
  File? get chatBgFile => _file(chatBgPath);
  File? get homeBgFile => _file(homeBgPath);
}
