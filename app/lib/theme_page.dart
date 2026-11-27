import 'dart:io';

import 'package:flutter/material.dart';

import 'color_picker.dart';
import 'crop_page.dart';
import 'history_db.dart';
import 'haptics.dart';
import 'prefs.dart';
import 'theme.dart';
import 'package:image_picker/image_picker.dart';

/// 主题：只有全局主题颜色 + 主页背景
class ThemePage extends StatefulWidget {
  const ThemePage({super.key, this.palette, this.showHomeBg = true});

  /// 为空时用全局配色
  final Palette? palette;

  /// 是否显示「主页背景」这一块
  final bool showHomeBg;

  @override
  State<ThemePage> createState() => _ThemePageState();
}

class _ThemePageState extends State<ThemePage> {
  final _picker = ImagePicker();

  Future<void> _pickHomeBg() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 2560,
      maxHeight: 2560,
      imageQuality: 90,
    );
    if (picked == null || !mounted) return;
    final size = MediaQuery.of(context).size;
    final cropped = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => CropPage(
          file: File(picked.path),
          aspectRatio: size.width / size.height,
          outputSize: 1440,
          title: '裁剪主页背景',
        ),
      ),
    );
    if (cropped == null) return;
    final stored = await copyToAppDir(File(cropped), prefix: 'homebg');
    final old = AppPrefs.instance.homeBgPath;
    await AppPrefs.instance.setHomeBg(stored);
    if (old != null && old.isNotEmpty) {
      try {
        await FileImage(File(old)).evict();
      } catch (_) {}
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppPrefs.instance,
      builder: (context, _) {
        final prefs = AppPrefs.instance;
        final palette = widget.palette ?? prefs.palette;
        final bg = prefs.homeBgFile;
        return Theme(
          data: buildTheme(palette),
          child: Scaffold(
          appBar: AppBar(title: const Text('主题')),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 40),
            children: [
              const _Section('主题颜色'),
              _paletteGrid(
                palette,
                current: prefs.paletteId,
                onPick: (id) async {
                  if (id == null) return;
                  await prefs.setPalette(id);
                  if (mounted) setState(() {});
                },
              ),
              ListTile(
                leading: Icon(Icons.colorize, color: palette.accent),
                title: const Text('自定义主题颜色'),
                subtitle: Text('背景 / 主题 / 双方气泡',
                    style:
                        TextStyle(fontSize: 11, color: palette.fgWith(0.4))),
                trailing: const Icon(Icons.chevron_right),
                onTap: _editCustom,
              ),
              if (widget.showHomeBg) ...[
              const _Section('主页背景'),
              ListTile(
                leading: Icon(Icons.image_outlined, color: palette.accent),
                title: const Text('背景图片'),
                subtitle: Text(bg == null ? '未设置（使用主题底色）' : '已设置',
                    style:
                        TextStyle(fontSize: 11, color: palette.fgWith(0.4))),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (bg != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(bg,
                            width: 40, height: 40,
                            fit: BoxFit.cover, cacheWidth: 120),
                      ),
                    const SizedBox(width: 6),
                    const Icon(Icons.chevron_right),
                  ],
                ),
                onTap: _pickHomeBg,
              ),
              if (bg != null)
                ListTile(
                  leading: Icon(Icons.delete_outline, color: palette.fgWith(0.5)),
                  title: const Text('移除主页背景'),
                  onTap: () async {
                    await prefs.setHomeBg(null);
                    if (mounted) setState(() {});
                  },
                ),
              ListTile(
                title: Row(
                  children: [
                    const Text('背景不透明度'),
                    const Spacer(),
                    Text('${(prefs.bgOpacity * 100).round()}%',
                        style: TextStyle(
                            fontSize: 12, color: palette.fgWith(0.5))),
                  ],
                ),
                subtitle: Slider(
                  value: prefs.bgOpacity.clamp(0.1, 1.0),
                  min: 0.1,
                  max: 1.0,
                  divisions: 90,
                  onChanged: prefs.setBgOpacity,
                ),
              ),
              ],
            ],
          ),
          ),
        );
      },
    );
  }

  Widget _paletteGrid(
    Palette palette, {
    required String? current,
    required ValueChanged<String?> onPick,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final p in kPalettes)
            GestureDetector(
              onTap: () => onPick(p.id),
              child: Container(
                width: 74,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: current == p.id
                      ? p.accent.withValues(alpha: 0.18)
                      : palette.alt,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: current == p.id ? p.accent : palette.fgWith(0.12),
                    width: current == p.id ? 2 : 1,
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      decoration:
                          BoxDecoration(color: p.accent, shape: BoxShape.circle),
                    ),
                    const SizedBox(height: 6),
                    Text(p.name,
                        style: TextStyle(
                            fontSize: 11,
                            color: palette.fgWith(
                                current == p.id ? 0.9 : 0.55))),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _editCustom() async {
    final prefs = AppPrefs.instance;
    final palette = prefs.palette;
    final values = <String, Color>{
      'bg': Color(prefs.customBg),
      'accent': Color(prefs.customAccent),
      'mine': Color(prefs.customMine),
      'other': Color(prefs.customOther),
    };
    const labels = {
      'bg': '背景色',
      'accent': '主题色',
      'mine': '我的气泡',
      'other': '她的气泡',
    };
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('自定义主题颜色'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final k in labels.keys)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: values[k],
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: palette.fgWith(0.2)),
                    ),
                  ),
                  title: Text(labels[k]!),
                  onTap: () async {
                    final picked = await Navigator.of(context).push<Color>(
                      MaterialPageRoute(
                        builder: (_) => ColorPickerPage(
                          initial: values[k]!,
                          title: labels[k]!,
                        ),
                      ),
                    );
                    if (picked != null) setD(() => values[k] = picked);
                  },
                ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('保存')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await prefs.setCustomBg(values['bg']!.toARGB32());
    await prefs.setCustomAccent(values['accent']!.toARGB32());
    await prefs.setCustomMine(values['mine']!.toARGB32());
    await prefs.setCustomOther(values['other']!.toARGB32());
    await prefs.setPalette('custom');
    if (mounted) setState(() {});
  }
}

class _Section extends StatelessWidget {
  const _Section(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    // 直接用当前生效的主题色，换色后立刻跟着变
    final color = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Text(text,
          style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w600, color: color)),
    );
  }
}
