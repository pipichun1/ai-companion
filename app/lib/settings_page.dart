import 'dart:convert';
import 'dart:io';

import 'dart:convert';

import 'package:flutter/material.dart';

import 'app_config.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import 'color_picker.dart';
import 'chat_display_page.dart';
import 'haptics_page.dart';
import 'theme_page.dart';
import 'themed_route.dart';
import 'crop_page.dart';
import 'history_db.dart';
import 'prefs.dart';
import 'settings_store.dart';
import 'theme.dart';

const kAppVersion = '1.33.1 (84)';

/// 设置首页：分组入口
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, this.convId, this.paletteOverride});

  /// 不为空时，顶部显示"当前会话外观"，整页也用这个会话的配色
  final String? convId;

  /// 调用方已知的会话配色，传进来可避免首帧闪全局配色
  final Palette? paletteOverride;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  Conversation? _conv;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.convId == null) return;
    final c = await HistoryDb.convGet(widget.convId!);
    if (!mounted) return;
    setState(() => _conv = c);
  }

  /// 会话自己的配色优先，否则用全局
  Palette get _palette {
    if (widget.paletteOverride != null) {
      final saved = _conv;
      // 会话记录还没读到时，先用传入的配色，读到了再以数据库为准
      if (saved == null) return widget.paletteOverride!;
    }
    final c = _conv;
    if (c != null && c.customColors != null) {
      try {
        final m = jsonDecode(c.customColors!) as Map<String, dynamic>;
        Color pick(String k, Color fb) {
          final v = m[k];
          if (v is! String) return fb;
          return Color(int.parse(v.replaceFirst('#', ''), radix: 16) |
              0xFF000000);
        }

        final base = AppPrefs.instance.palette;
        return Palette.custom(
          bg: pick('bg', base.bg),
          accent: pick('accent', base.accent),
          bubbleMine: pick('mine', base.bubbleMine),
          bubbleOther: pick('other', base.bubbleOther),
        );
      } catch (_) {}
    }
    if (c != null && c.paletteId != null) return paletteById(c.paletteId);
    return AppPrefs.instance.palette;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppPrefs.instance,
      builder: (context, _) {
        final palette = _palette;
        return Theme(
          data: buildTheme(palette),
          child: Scaffold(
          appBar: AppBar(title: const Text('设置')),
          body: ListView(
            padding: const EdgeInsets.only(top: 8, bottom: 40),
            children: [
              if (widget.convId != null)
                _ConvAppearanceCard(
                  convId: widget.convId!,
                  palette: palette,
                  onChanged: _load,
                ),
              if (widget.convId == null)
                _entry(
                  context,
                  palette,
                  icon: Icons.palette_outlined,
                  title: '主题',
                  subtitle: '主题颜色、主页背景',
                  page: const ThemePage(),
                ),
              _entry(
                context,
                palette,
                icon: Icons.chat_bubble_outline,
                title: '聊天',
                subtitle: '字体大小、气泡透明度、毛玻璃',
                page: ChatDisplayPage(
                    palette: widget.convId == null ? null : _palette),
              ),
              if (widget.convId == null)
                _entry(
                  context,
                  palette,
                  icon: Icons.vibration,
                  title: '震动反馈',
                  subtitle: '总开关、她回消息时震动',
                  page: const HapticsPage(),
                ),
              if (widget.convId == null)
                AnimatedBuilder(
                  animation: AppPrefs.instance,
                  builder: (context, _) => Padding(
                    padding: const EdgeInsets.fromLTRB(4, 2, 4, 2),
                    child: SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 2),
                      secondary: Icon(Icons.auto_awesome,
                          size: 22, color: palette.fgWith(0.75)),
                      title: Text('让她自己换装扮',
                          style: TextStyle(
                              fontSize: 15, color: palette.fg)),
                      subtitle: Text('她偶尔会自己挑一张头像或背景（一天最多一次）',
                          style: TextStyle(
                              fontSize: 11.5, color: palette.fgWith(0.45))),
                      value: AppPrefs.instance.selfDress,
                      onChanged: (v) => AppPrefs.instance.setSelfDress(v),
                    ),
                  ),
                ),
              _entry(
                context,
                palette,
                icon: Icons.link,
                title: '连接',
                subtitle: '服务器地址、会话 ID、令牌',
                page: ConnectionPage(
                    palette: widget.convId == null ? null : _palette),
              ),
              _entry(
                context,
                palette,
                icon: Icons.storage_outlined,
                title: '数据',
                subtitle: '清空本地记录、版本信息',
                page: DataPage(
                    palette: widget.convId == null ? null : _palette),
              ),
              const SizedBox(height: 30),
              Center(
                child: Text('${AppConfig.brand} App · 版本 $kAppVersion',
                    style: TextStyle(
                        fontSize: 11, color: palette.fgWith(0.28))),
              ),
            ],
          ),
          ),
        );
      },
    );
  }

  Widget _entry(
    BuildContext context,
    Palette palette, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget page,
  }) {
    return ListTile(
      leading: Icon(icon, color: palette.accent),
      title: Text(title),
      subtitle: Text(subtitle,
          style: TextStyle(fontSize: 11, color: palette.fgWith(0.4))),
      trailing: const Icon(Icons.chevron_right),
      onTap: () =>
          Navigator.of(context).push(themedRoute(palette, page)),
    );
  }
}

/// 单个会话的外观：头像 / 背景 / 配色（只影响这一个会话）
class _ConvAppearanceCard extends StatefulWidget {
  const _ConvAppearanceCard({required this.convId, required this.palette, this.onChanged});
  final String convId;
  final Palette palette;
  final VoidCallback? onChanged;

  @override
  State<_ConvAppearanceCard> createState() => _ConvAppearanceCardState();
}

class _ConvAppearanceCardState extends State<_ConvAppearanceCard> {
  final _picker = ImagePicker();
  Conversation? _conv;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = await HistoryDb.convGet(widget.convId);
    if (!mounted) return;
    setState(() {
      _conv = c;
      _loaded = true;
    });
  }

  Future<void> _save() async {
    final c = _conv;
    if (c == null) return;
    try {
      await HistoryDb.convUpsert(c);
      if (mounted) setState(() {});
      widget.onChanged?.call();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('保存失败：$e')));
    }
  }

  Widget _preview(Palette palette, String? path, {required bool circle}) {
    final exists = path != null && File(path).existsSync();
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: palette.alt,
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circle ? null : BorderRadius.circular(8),
        image: exists
            ? DecorationImage(
                image: FileImage(File(path)), fit: BoxFit.cover)
            : null,
      ),
      child: exists
          ? null
          : Icon(Icons.image_outlined,
              size: 18, color: palette.fgWith(0.35)),
    );
  }

  Future<void> _pickImage({required bool avatar}) async {
    final c = _conv;
    if (c == null) return;
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: avatar ? 1024 : 2560,
      maxHeight: avatar ? 1024 : 2560,
      imageQuality: 90,
    );
    if (picked == null || !mounted) return;
    final size = MediaQuery.of(context).size;
    final cropped = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => CropPage(
          file: File(picked.path),
          aspectRatio: avatar ? 1.0 : size.width / size.height,
          outputSize: avatar ? 512 : 1440,
          title: avatar ? '裁剪她的头像' : '裁剪聊天背景',
        ),
      ),
    );
    if (cropped == null) return;
    final stored = await copyToAppDir(File(cropped),
        prefix: avatar ? 'avatar' : 'chatbg');
    final old = avatar ? c.avatarPath : c.bgPath;
    if (avatar) {
      c.avatarPath = stored;
    } else {
      c.bgPath = stored;
    }
    if (old != null && old.isNotEmpty) {
      try {
        await FileImage(File(old)).evict();
      } catch (_) {}
    }
    await _save();
  }

  Future<void> _pickPalette() async {
    final c = _conv;
    if (c == null) return;
    final base = widget.palette;
    final picked = await showModalBottomSheet<String?>(
      context: context,
      backgroundColor: base.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.colorize, size: 20),
              title: const Text('自定义颜色…'),
              onTap: () => Navigator.pop(ctx, '__custom__'),
            ),
            ListTile(
              leading: const Icon(Icons.settings_backup_restore, size: 20),
              title: const Text('跟随全局'),
              trailing: c.paletteId == null && c.customColors == null
                  ? Icon(Icons.check, size: 18, color: base.accent)
                  : null,
              onTap: () => Navigator.pop(ctx, '__global__'),
            ),
            for (final p in kPalettes)
              ListTile(
                leading: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    gradient:
                        LinearGradient(colors: [p.accent, p.bubbleMine]),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                title: Text(p.name),
                trailing: c.paletteId == p.id
                    ? Icon(Icons.check, size: 18, color: base.accent)
                    : null,
                onTap: () => Navigator.pop(ctx, p.id),
              ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    if (picked == '__custom__') {
      await _editColors(c);
      return;
    }
    c.paletteId = picked == '__global__' ? null : picked;
    c.customColors = null;
    await _save();
  }

  String _hex(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  Color _parse(String? v, Color fallback) {
    if (v == null || v.isEmpty) return fallback;
    try {
      return Color(int.parse(v.replaceFirst('#', ''), radix: 16) | 0xFF000000);
    } catch (_) {
      return fallback;
    }
  }

  Future<void> _editColors(Conversation c) async {
    final base = widget.palette;
    final colors = <String, String>{
      'bg': _hex(base.bg),
      'accent': _hex(base.accent),
      'mine': _hex(base.bubbleMine),
      'other': _hex(base.bubbleOther),
    };
    if (c.customColors != null) {
      try {
        final m = jsonDecode(c.customColors!) as Map<String, dynamic>;
        m.forEach((k, v) => colors[k] = v as String);
      } catch (_) {}
    }
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
          title: const Text('这个对话的配色'),
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
                      color: _parse(colors[k], base.accent),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: base.fgWith(0.2)),
                    ),
                  ),
                  title: Text(labels[k]!),
                  onTap: () async {
                    final picked = await Navigator.of(context).push<Color>(
                      MaterialPageRoute(
                        builder: (_) => ColorPickerPage(
                          initial: _parse(colors[k], base.accent),
                          title: labels[k]!,
                        ),
                      ),
                    );
                    if (picked != null) setD(() => colors[k] = _hex(picked));
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
    c.customColors = jsonEncode(colors);
    c.paletteId = null;
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    if (!_loaded) return const SizedBox.shrink();
    final c = _conv;
    if (c == null) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Text('这个对话还没有外观记录',
            style: TextStyle(fontSize: 12, color: palette.fgWith(0.5))),
      );
    }
    final currentPalette = c.customColors != null
        ? '自定义'
        : (c.paletteId == null ? '跟随全局' : paletteById(c.paletteId).name);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
          child: Text('当前会话外观',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: palette.accent)),
        ),
        ListTile(
          leading: _preview(palette, c.avatarPath, circle: true),
          title: const Text('她的头像'),
          subtitle: Text(
              (c.avatarPath != null && File(c.avatarPath!).existsSync())
                  ? '已单独设置'
                  : '未设置',
              style: TextStyle(fontSize: 11, color: palette.fgWith(0.4))),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _pickImage(avatar: true),
        ),
        ListTile(
          leading: _preview(palette, c.bgPath, circle: false),
          title: const Text('聊天背景'),
          subtitle: Text(
              (c.bgPath != null && File(c.bgPath!).existsSync())
                  ? '已单独设置'
                  : '未设置',
              style: TextStyle(fontSize: 11, color: palette.fgWith(0.4))),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _pickImage(avatar: false),
        ),
        ListTile(
          leading: Icon(Icons.palette_outlined, color: palette.accent),
          title: const Text('配色'),
          subtitle: Text(currentPalette,
              style: TextStyle(fontSize: 11, color: palette.fgWith(0.4))),
          trailing: const Icon(Icons.chevron_right),
          onTap: _pickPalette,
        ),
        const Divider(height: 24),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = AppPrefs.instance.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      child: Text(text,
          style: TextStyle(
              fontSize: 12,
              color: palette.fgWith(0.4),
              fontWeight: FontWeight.w600)),
    );
  }
}

/// 无极滑块（1% 精度）
class _PercentSlider extends StatelessWidget {
  const _PercentSlider({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = 0.0,
    this.max = 1.0,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final void Function(double) onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = AppPrefs.instance.palette;
    final clamped = value.clamp(min, max);
    final pct = ((clamped - min) / (max - min) * 100).round();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          SizedBox(width: 78, child: Text(label)),
          Expanded(
            child: Slider(
              value: clamped,
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 44,
            child: Text('$pct%',
                textAlign: TextAlign.right,
                style: TextStyle(color: palette.fgWith(0.55), fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── 配色 ─────────────────────────

class PalettePage extends StatefulWidget {
  const PalettePage({super.key});

  @override
  State<PalettePage> createState() => _PalettePageState();
}

class _PalettePageState extends State<PalettePage> {
  Future<void> _pickColor({
    required String title,
    required Color current,
    required Future<void> Function(int) apply,
  }) async {
    final picked = await Navigator.of(context).push<Color>(
      MaterialPageRoute(
        builder: (_) => ColorPickerPage(initial: current, title: title),
      ),
    );
    if (picked == null) return;
    await apply(picked.toARGB32());
    await AppPrefs.instance.setPalette('custom');
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppPrefs.instance,
      builder: (context, _) {
        final prefs = AppPrefs.instance;
        final palette = prefs.palette;
        final isCustom = prefs.paletteId == 'custom';

        return Scaffold(
          appBar: AppBar(title: const Text('配色')),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 40),
            children: [
              const _Section('预设'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    ...kPalettes.map((p) {
                      final selected = prefs.paletteId == p.id;
                      return GestureDetector(
                        onTap: () async {
                          await prefs.setPalette(p.id);
                          if (mounted) setState(() {});
                        },
                        child: Column(
                          children: [
                            Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                color: p.bg,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: selected ? p.accent : p.fgWith(0.12),
                                  width: selected ? 2.5 : 1,
                                ),
                              ),
                              child: Stack(
                                children: [
                                  Positioned(
                                    left: 8,
                                    bottom: 10,
                                    child: Container(
                                      width: 26,
                                      height: 12,
                                      decoration: BoxDecoration(
                                        color: p.bubbleOther,
                                        borderRadius:
                                            BorderRadius.circular(6),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    right: 8,
                                    top: 10,
                                    child: Container(
                                      width: 26,
                                      height: 12,
                                      decoration: BoxDecoration(
                                        color: p.bubbleMine,
                                        borderRadius:
                                            BorderRadius.circular(6),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(p.name,
                                style: TextStyle(
                                    fontSize: 11,
                                    color: selected
                                        ? p.accent
                                        : palette.fgWith(0.5))),
                          ],
                        ),
                      );
                    }),
                    _customCard(prefs, isCustom),
                  ],
                ),
              ),
              const _Section('自定义颜色'),
              _colorRow(
                prefs,
                '底色',
                Color(prefs.customBg),
                () => _pickColor(
                  title: '选择底色',
                  current: Color(prefs.customBg),
                  apply: prefs.setCustomBg,
                ),
              ),
              _colorRow(
                prefs,
                '强调色',
                Color(prefs.customAccent),
                () => _pickColor(
                  title: '选择强调色',
                  current: Color(prefs.customAccent),
                  apply: prefs.setCustomAccent,
                ),
              ),
              _colorRow(
                prefs,
                '我的气泡',
                Color(prefs.customMine),
                () => _pickColor(
                  title: '我的气泡颜色',
                  current: Color(prefs.customMine),
                  apply: prefs.setCustomMine,
                ),
              ),
              _colorRow(
                prefs,
                '她的气泡',
                Color(prefs.customOther),
                () => _pickColor(
                  title: '她的气泡颜色',
                  current: Color(prefs.customOther),
                  apply: prefs.setCustomOther,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Text(
                  isCustom
                      ? '当前正在使用自定义配色'
                      : '点上面的「自定义」立刻切换，再调下面四个颜色',
                  style: TextStyle(fontSize: 11, color: palette.fgWith(0.4)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _customCard(AppPrefs prefs, bool selected) {
    final palette = prefs.palette;
    return GestureDetector(
      onTap: () async {
        await prefs.setPalette('custom');
        if (mounted) setState(() {});
      },
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Color(prefs.customBg),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? Color(prefs.customAccent) : palette.fgWith(0.25),
                width: selected ? 2.5 : 1,
              ),
            ),
            child: Stack(
              children: [
                Positioned(
                  left: 8,
                  bottom: 10,
                  child: Container(
                    width: 26,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Color(prefs.customOther),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
                Positioned(
                  right: 8,
                  top: 10,
                  child: Container(
                    width: 26,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Color(prefs.customMine),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
                if (selected)
                  Positioned(
                    right: 4,
                    bottom: 4,
                    child: Icon(Icons.check_circle,
                        size: 14, color: Color(prefs.customAccent)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text('自定义',
              style: TextStyle(
                  fontSize: 11,
                  color: selected
                      ? Color(prefs.customAccent)
                      : palette.fgWith(0.5))),
        ],
      ),
    );
  }

  Widget _colorRow(AppPrefs prefs, String label, Color color, VoidCallback onTap) {
    final palette = prefs.palette;
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: palette.fgWith(0.2)),
        ),
      ),
      title: Text(label),
      trailing: Text(
        '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
        style: TextStyle(fontSize: 11, color: palette.fgWith(0.45)),
      ),
      onTap: onTap,
    );
  }
}

// ───────────────────── 头像与背景 ─────────────────────

class AppearancePage extends StatefulWidget {
  const AppearancePage({super.key});

  @override
  State<AppearancePage> createState() => _AppearancePageState();
}

class _AppearancePageState extends State<AppearancePage> {
  final _picker = ImagePicker();

  Future<String?> _pickAndCrop(
      {required bool square, required String title}) async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: square ? 1024 : 2560,
      maxHeight: square ? 1024 : 2560,
      imageQuality: 90,
    );
    if (picked == null || !mounted) return null;
    final size = MediaQuery.of(context).size;
    return Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => CropPage(
          file: File(picked.path),
          aspectRatio: square ? 1.0 : size.width / size.height,
          outputSize: square ? 512 : 1440,
          title: title,
        ),
      ),
    );
  }

  Future<void> _setAvatar({required bool mine}) async {
    final path = await _pickAndCrop(
        square: true, title: mine ? '裁剪我的头像' : '裁剪她的头像');
    if (path == null) return;
    final stored = await copyToAppDir(File(path), prefix: mine ? 'me' : 'her');
    if (mine) {
      await AppPrefs.instance.setMyAvatar(stored);
    } else {
      await AppPrefs.instance.setAvatar(stored);
    }
    if (mounted) setState(() {});
  }

  Future<void> _setImage({
    required String title,
    required String prefix,
    required Future<void> Function(String?) set,
  }) async {
    final path = await _pickAndCrop(square: false, title: title);
    if (path == null) return;
    final stored = await copyToAppDir(File(path), prefix: prefix);
    await set(stored);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppPrefs.instance,
      builder: (context, _) {
        final prefs = AppPrefs.instance;
        final palette = prefs.palette;
        return Scaffold(
          appBar: AppBar(title: const Text('头像与背景')),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 40),
            children: [
              const _Section('头像'),
              _avatarTile(
                prefs: prefs,
                label: '她的头像',
                file: prefs.avatarFile,
                onPick: () => _setAvatar(mine: false),
                onReset: () => prefs.setAvatar(null),
              ),
              _avatarTile(
                prefs: prefs,
                label: '我的头像',
                file: prefs.myAvatarFile,
                onPick: () => _setAvatar(mine: true),
                onReset: () => prefs.setMyAvatar(null),
              ),
              const _Section('背景'),
              _imageTile(
                prefs: prefs,
                icon: Icons.wallpaper,
                label: '聊天背景',
                sub: '对话页那张图',
                file: prefs.chatBgFile,
                onPick: () => _setImage(
                  title: '裁剪聊天背景',
                  prefix: 'bg',
                  set: prefs.setChatBg,
                ),
                onReset: () => prefs.setChatBg(null),
              ),
              _imageTile(
                prefs: prefs,
                icon: Icons.view_list,
                label: '消息列表背景',
                sub: '「消息」首页那张图',
                file: prefs.homeBgFile,
                onPick: () => _setImage(
                  title: '裁剪列表背景',
                  prefix: 'homebg',
                  set: prefs.setHomeBg,
                ),
                onReset: () => prefs.setHomeBg(null),
              ),
              _PercentSlider(
                label: '背景浓度',
                value: prefs.bgOpacity,
                onChanged: (v) => prefs.setBgOpacity(v),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Text('浓度越高，背景图越明显',
                    style: TextStyle(fontSize: 11, color: palette.fgWith(0.4))),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _avatarTile({
    required AppPrefs prefs,
    required String label,
    required File? file,
    required VoidCallback onPick,
    required Future<void> Function() onReset,
  }) {
    return ListTile(
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: prefs.palette.alt,
          image: file != null
              ? DecorationImage(image: FileImage(file), fit: BoxFit.cover)
              : null,
        ),
        child: file == null
            ? Icon(Icons.set_meal, color: prefs.palette.fgWith(0.6))
            : null,
      ),
      title: Text(label),
      subtitle: Text('点一下从相册选，可裁剪',
          style: TextStyle(fontSize: 11, color: prefs.palette.fgWith(0.4))),
      trailing: file == null
          ? const Icon(Icons.chevron_right)
          : IconButton(
              icon: const Icon(Icons.restart_alt, size: 20),
              onPressed: () async {
                await onReset();
                if (mounted) setState(() {});
              },
            ),
      onTap: onPick,
    );
  }

  Widget _imageTile({
    required AppPrefs prefs,
    required IconData icon,
    required String label,
    required String sub,
    required File? file,
    required VoidCallback onPick,
    required Future<void> Function() onReset,
  }) {
    return ListTile(
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: prefs.palette.alt,
          image: file != null
              ? DecorationImage(image: FileImage(file), fit: BoxFit.cover)
              : null,
        ),
        child: file == null ? Icon(icon, color: prefs.palette.fgWith(0.6)) : null,
      ),
      title: Text(label),
      subtitle: Text(sub,
          style: TextStyle(fontSize: 11, color: prefs.palette.fgWith(0.4))),
      trailing: file == null
          ? const Icon(Icons.chevron_right)
          : IconButton(
              icon: const Icon(Icons.restart_alt, size: 20),
              onPressed: () async {
                await onReset();
                if (mounted) setState(() {});
              },
            ),
      onTap: onPick,
    );
  }
}

// ───────────────────── 聊天显示 ─────────────────────

class DisplayPage extends StatefulWidget {
  const DisplayPage({super.key});

  @override
  State<DisplayPage> createState() => _DisplayPageState();
}

class _DisplayPageState extends State<DisplayPage> {
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppPrefs.instance,
      builder: (context, _) {
        final prefs = AppPrefs.instance;
        final palette = prefs.palette;
        return Scaffold(
          appBar: AppBar(title: const Text('聊天显示')),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 40),
            children: [
              const _Section('气泡'),
              _PercentSlider(
                label: '透明度',
                value: prefs.bubbleOpacity,
                min: 0.2,
                onChanged: (v) => prefs.setBubbleOpacity(v),
              ),
              const _Section('字体大小'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: List.generate(3, (i) {
                    const names = ['小', '中', '大'];
                    final selected = prefs.fontScaleIdx == i;
                    return Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: ChoiceChip(
                        label: Text(names[i]),
                        selected: selected,
                        onSelected: (_) async {
                          await prefs.setFontScaleIdx(i);
                          if (mounted) setState(() {});
                        },
                      ),
                    );
                  }),
                ),
              ),
              const _Section('输入栏'),
              SwitchListTile(
                title: const Text('毛玻璃'),
                subtitle: Text('背景图模糊着透上来（略费电）',
                    style:
                        TextStyle(fontSize: 11, color: palette.fgWith(0.4))),
                value: prefs.glassComposer,
                onChanged: (v) async {
                  await prefs.setGlassComposer(v);
                  if (mounted) setState(() {});
                },
              ),
              if (prefs.glassComposer)
                _PercentSlider(
                  label: '模糊强度',
                  value: prefs.glassSigma / 40,
                  onChanged: (v) => prefs.setGlassSigma(v * 40),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Text(
                    prefs.glassComposer
                        ? '当前模糊 σ = ${prefs.glassSigma.toStringAsFixed(1)}（0 = 只透明不模糊）'
                        : '开启后才能调模糊强度',
                    style: TextStyle(fontSize: 11, color: palette.fgWith(0.4))),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ───────────────────── 连接 ─────────────────────

class ConnectionPage extends StatefulWidget {
  const ConnectionPage({super.key, this.palette});
  final Palette? palette;

  @override
  State<ConnectionPage> createState() => _ConnectionPageState();
}

class _ConnectionPageState extends State<ConnectionPage> {
  final _baseCtl = TextEditingController();
  final _tokenCtl = TextEditingController();
  final _convCtl = TextEditingController();
  bool _showToken = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await Settings.load();
    if (!mounted) return;
    setState(() {
      _baseCtl.text = s.base;
      _tokenCtl.text = s.token;
      _convCtl.text = s.conv;
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette ?? AppPrefs.instance.palette;
    return Theme(
      data: buildTheme(palette),
      child: Scaffold(
      appBar: AppBar(title: const Text('连接')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(top: 8, bottom: 40),
              children: [
                _field(_baseCtl, '服务器地址'),
                _field(_convCtl, '会话 ID'),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                  child: TextField(
                    controller: _tokenCtl,
                    obscureText: !_showToken,
                    maxLines: _showToken ? 3 : 1,
                    decoration: InputDecoration(
                      labelText: '访问令牌',
                      suffixIcon: IconButton(
                        icon: Icon(
                            _showToken ? Icons.visibility_off : Icons.visibility),
                        onPressed: () =>
                            setState(() => _showToken = !_showToken),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: _checkServer,
                        icon: const Icon(Icons.wifi_tethering, size: 18),
                        label: const Text('检查服务器'),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: _save,
                          child: const Text('保存'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
      ),
    );
  }

  Future<void> _checkServer() async {
    final base = _baseCtl.text.trim();
    final token = _tokenCtl.text.trim();
    if (base.isEmpty) {
      _showCheck('先填服务器地址');
      return;
    }
    String b = base;
    while (b.endsWith('/')) {
      b = b.substring(0, b.length - 1);
    }
    final bridge = '$b/api/v1/plugins/extensions/v1';
    final lines = <String>[];

    try {
      final models = await http
          .get(Uri.parse('$bridge/models'),
              headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 10));
      lines.add(models.statusCode == 200
          ? '✅ 聊天接口正常'
          : '❌ 聊天接口返回 ${models.statusCode}');
    } catch (e) {
      lines.add('❌ 连不上：$e');
    }

    try {
      final p = await http
          .get(Uri.parse('$bridge/personas'),
              headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 10));
      if (p.statusCode == 200) {
        final data =
            jsonDecode(utf8.decode(p.bodyBytes)) as Map<String, dynamic>;
        final list = (data['data'] as List?) ?? [];
        final names = list.map((e) => (e['name'] ?? '?').toString()).join('、');
        lines.add('✅ 人格接口正常，共 ${list.length} 个：$names');
      } else if (p.statusCode == 404) {
        lines.add('⚠️ 没有 /personas 接口，可能缺 openai_bridge 插件');
      } else {
        lines.add('⚠️ 人格接口返回 ${p.statusCode}');
      }
    } catch (e) {
      lines.add('⚠️ 人格接口异常：$e');
    }

    _showCheck(lines.isEmpty ? '没拿到结果' : lines.join('\n'));
  }

  void _showCheck(String text) {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('连接检查'),
        content: Text(text, style: const TextStyle(fontSize: 13)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('好')),
        ],
      ),
    );
  }
  Widget _field(TextEditingController c, String label) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        child: TextField(
            controller: c, decoration: InputDecoration(labelText: label)),
      );

  Future<void> _save() async {
    final s = Settings(
      _baseCtl.text.trim(),
      _tokenCtl.text.trim(),
      _convCtl.text.trim(),
    );
    await s.save();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已保存')));
  }
}

// ───────────────────── 数据 ─────────────────────

class DataPage extends StatelessWidget {
  const DataPage({super.key, this.palette});
  final Palette? palette;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppPrefs.instance,
      builder: (context, _) {
        final palette = AppPrefs.instance.palette;
        return Scaffold(
          appBar: AppBar(title: const Text('数据')),
          body: ListView(
            children: [
              ListTile(
                leading:
                    const Icon(Icons.delete_outline, color: Colors.redAccent),
                title: const Text('清空本地聊天记录',
                    style: TextStyle(color: Colors.redAccent)),
                subtitle: Text('只删手机上的记录，服务端的记忆不受影响',
                    style: TextStyle(fontSize: 11, color: palette.fgWith(0.4))),
                onTap: () => _clear(context),
              ),
              const Divider(height: 32),
              const ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('版本'),
                subtitle: Text(kAppVersion),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _clear(BuildContext context) async {
    final s = await Settings.load();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空聊天记录？'),
        content: const Text('只删手机上的记录，服务端的记忆不受影响。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true), child: const Text('清空')),
        ],
      ),
    );
    if (ok != true) return;
    await HistoryDb.clear(s.conv);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已清空')));
  }
}
