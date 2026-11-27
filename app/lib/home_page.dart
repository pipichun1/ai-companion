import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'app_config.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'album_page.dart';
import 'chat_api.dart';
import 'color_picker.dart';
import 'crop_page.dart';
import 'haptics.dart';
import 'history_db.dart';
import 'main.dart';
import 'prefs.dart';
import 'settings_page.dart';
import 'settings_store.dart';
import 'theme.dart';
import 'themed_route.dart';

class MessagesHome extends StatefulWidget {
  const MessagesHome({super.key});

  @override
  State<MessagesHome> createState() => _MessagesHomeState();
}

class _MessagesHomeState extends State<MessagesHome> {
  List<Conversation> _convs = [];
  final Map<String, Msg?> _lastMsg = {};
  final Map<String, int> _unread = {};
  final _homeKey = GlobalKey<ScaffoldState>();
  bool _loading = true;
  List<Map<String, dynamic>> _personas = [];

  @override
  void initState() {
    super.initState();
    _refresh();
    _warmup();
  }

  Future<void> _warmup() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString('personas_cache');
    if (raw != null) {
      try {
        final list = (jsonDecode(raw) as List)
            .map((e) => e as Map<String, dynamic>)
            .toList();
        if (mounted) setState(() => _personas = list);
      } catch (_) {}
    }
    try {
      final s = await Settings.load();
      final api = ChatApi(base: s.base, token: s.token, conv: s.conv);
      await api.warmup();
      final list = await api.listPersonas();
      await p.setString('personas_cache', jsonEncode(list));
      if (mounted) setState(() => _personas = list);
    } catch (_) {}
  }

  bool _migrated = false;

  /// 老版本把头像/背景存在全局，现在归会话所有，搬迁一次
  Future<void> _migrateLegacyAppearance(List<Conversation> convs) async {
    if (_migrated || convs.isEmpty) return;
    _migrated = true;
    final prefs = AppPrefs.instance;
    final first = convs.first;
    var changed = false;
    if (first.avatarPath == null && prefs.avatarPath != null) {
      first.avatarPath = prefs.avatarPath;
      changed = true;
    }
    if (first.bgPath == null && prefs.chatBgPath != null) {
      first.bgPath = prefs.chatBgPath;
      changed = true;
    }
    if (changed) await HistoryDb.convUpsert(first);
  }

  Future<void> _refresh() async {
    final s = await Settings.load();
    var convs = await HistoryDb.convList();
    if (convs.isEmpty) {
      await HistoryDb.convUpsert(Conversation(
        conv: s.conv,
        name: AppConfig.brand,
        persona: 'sese-fish-persona.md',
        createdAt: DateTime.now(),
      ));
      convs = await HistoryDb.convList();
    }
    await _migrateLegacyAppearance(convs);
    for (final c in convs) {
      final recent = await HistoryDb.recent(c.conv, limit: 1);
      _lastMsg[c.conv] = recent.isEmpty ? null : recent.last;
      _unread[c.conv] = await HistoryDb.unread(c.conv, c.lastRead);
    }
    if (!mounted) return;
    setState(() {
      _convs = convs;
      _loading = false;
    });
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h >= 5 && h < 11) return '早上好';
    if (h >= 11 && h < 13) return '中午好';
    if (h >= 13 && h < 18) return '下午好';
    if (h >= 18 && h < 23) return '晚上好';
    return '这么晚还没睡';
  }

  String _dateLine() {
    final now = DateTime.now();
    const week = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return '${now.month} 月 ${now.day} 日 · ${week[now.weekday - 1]}';
  }

  String _preview(Conversation c) {
    final m = _lastMsg[c.conv];
    if (m == null) return '还没有聊过，点进去说句话吧';
    var text = m.text.replaceAll('\n', ' ').trim();
    if (m.imagePath != null && text.isEmpty) text = '[图片]';
    if (m.imagePath != null && text.isNotEmpty) text = '[图片] $text';
    if (text.length > 22) text = '${text.substring(0, 22)}…';
    return m.mine ? '我: $text' : text;
  }

  String _timeLabel(Conversation c) {
    final m = _lastMsg[c.conv];
    if (m == null) return '';
    final now = DateTime.now();
    final t = m.time;
    if (t.year == now.year && t.month == now.month && t.day == now.day) {
      return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    }
    final diff = now.difference(t).inDays;
    if (diff == 1) return '昨天';
    if (diff < 7) return '$diff 天前';
    return '${t.month}/${t.day}';
  }

  Palette _convPalette(Conversation c) {
    final base = AppPrefs.instance.palette;
    if (c.customColors != null) {
      try {
        final m = jsonDecode(c.customColors!) as Map<String, dynamic>;
        Color pick(String k, Color fb) {
          final v = m[k];
          if (v is! String) return fb;
          return Color(
              int.parse(v.replaceFirst('#', ''), radix: 16) | 0xFF000000);
        }

        return Palette.custom(
          bg: pick('bg', base.bg),
          accent: pick('accent', base.accent),
          bubbleMine: pick('mine', base.bubbleMine),
          bubbleOther: pick('other', base.bubbleOther),
        );
      } catch (_) {}
    }
    if (c.paletteId != null) return paletteById(c.paletteId);
    return base;
  }
  /// 进会话前把背景/头像先解码好，避免第一帧空一下
  Future<void> _precacheConversation(Conversation c) async {
    final files = <File>[];
    if (c.bgPath != null && File(c.bgPath!).existsSync()) {
      files.add(File(c.bgPath!));
    }
    if (c.avatarPath != null && File(c.avatarPath!).existsSync()) {
      files.add(File(c.avatarPath!));
    }
    final mine = AppPrefs.instance.myAvatarFile;
    if (mine != null) files.add(mine);
    for (final f in files) {
      try {
        await precacheImage(FileImage(f), context);
      } catch (_) {}
    }
  }

  Future<void> _openChat(Conversation c, {String? personaLabel}) async {
    await _precacheConversation(c);
    if (!mounted) return;
    await Navigator.of(context).push(
      themedRoute(
        _convPalette(c),
        ChatPage(
          conv: c.conv,
          name: c.name,
          personaName: personaLabel,
          avatarPath: c.avatarPath,
          bgPath: c.bgPath,
          paletteId: c.paletteId,
          customColors: c.customColors,
          apiBase: c.apiBase,
          apiKey: c.apiKey,
          model: c.model,
          systemNote: c.systemNote,
        ),
      ),
    );
    await HistoryDb.convMarkRead(c.conv, DateTime.now().millisecondsSinceEpoch);
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppPrefs.instance,
      builder: (context, _) => _buildHome(),
    );
  }

  Widget _buildHome() {
    final prefs = AppPrefs.instance;
    final palette = prefs.homePalette;
    final bg = prefs.homeBgFile;

    return Scaffold(
      key: _homeKey,
      backgroundColor: palette.bg,
      drawer: _homeDrawer(palette),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => _homeKey.currentState?.openDrawer(),
        ),
        titleSpacing: 0,
        title: const SizedBox.shrink(),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16, top: 6, bottom: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_greeting(),
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w700)),
                const SizedBox(height: 1),
                Text(_dateLine(),
                    style:
                        TextStyle(fontSize: 11, color: palette.fgWith(0.45))),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: palette.accent,
        foregroundColor: Colors.white,
        onPressed: _createConversation,
        child: const Icon(Icons.add),
      ),
      body: Container(
        decoration: BoxDecoration(
          color: palette.bg,
          image: bg != null
              ? DecorationImage(
                  image: FileImage(bg),
                  fit: BoxFit.cover,
                  opacity: prefs.bgOpacity,
                  filterQuality: FilterQuality.high,
                )
              : null,
        ),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _refresh,
                child: ReorderableListView.builder(
                  padding: const EdgeInsets.only(bottom: 90),
                  itemCount: _convs.length,
                  onReorder: _onReorder,
                  onReorderStart: (_) => Haptics.medium(),
                  onReorderEnd: (_) => Haptics.light(),
                  itemBuilder: (context, i) {
                    final c = _convs[i];
                    return _tile(
                      key: ValueKey(c.conv),
                      palette: palette,
                      conv: c,
                      preview: _preview(c),
                      time: _timeLabel(c),
                      badge: _unread[c.conv] ?? 0,
                      onTap: () => _openChat(c),
                      onMenu: () => _convMenu(c),
                    );
                  },
                ),
              ),
      ),
    );
  }

  /// 删会话的实际清理（界面已经先移除了）
  Future<void> _purgeConversation(Conversation c) async {
    try {
      await HistoryDb.convDelete(c.conv);
      await HistoryDb.clear(c.conv);
      await HistoryDb.convReorder(_convs.map((e) => e.conv).toList());
    } catch (_) {}
  }
  Future<void> _onReorder(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex -= 1;
    final moved = _convs.removeAt(oldIndex);
    _convs.insert(newIndex, moved);
    setState(() {});
    Haptics.medium();
    try {
      await HistoryDb.convReorder(_convs.map((e) => e.conv).toList());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('保存顺序失败：$e')));
      }
    }
  }

  Future<void> _convMenu(Conversation c) async {
    Haptics.medium();
    final palette = AppPrefs.instance.palette;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline, size: 20),
              title: const Text('改名'),
              onTap: () async {
                Navigator.pop(ctx);
                final ctl = TextEditingController(text: c.name);
                final name = await showDialog<String>(
                  context: context,
                  builder: (d) => AlertDialog(
                    title: const Text('改个名字'),
                    content: TextField(
                      controller: ctl,
                      autofocus: true,
                      decoration: const InputDecoration(hintText: '她的称呼'),
                    ),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(d),
                          child: const Text('取消')),
                      FilledButton(
                          onPressed: () => Navigator.pop(d, ctl.text.trim()),
                          child: const Text('保存')),
                    ],
                  ),
                );
                if (name == null || name.isEmpty) return;
                c.name = name;
                await HistoryDb.convUpsert(c);
                _refresh();
              },
            ),
            ListTile(
              leading: const Icon(Icons.face_retouching_natural, size: 20),
              title: const Text('换头像'),
              onTap: () async {
                Navigator.pop(ctx);
                await _pickConvImage(c, avatar: true);
              },
            ),
            ListTile(
              leading: const Icon(Icons.wallpaper, size: 20),
              title: const Text('换聊天背景'),
              onTap: () async {
                Navigator.pop(ctx);
                await _pickConvImage(c, avatar: false);
              },
            ),
            ListTile(
              leading: const Icon(Icons.palette_outlined, size: 20),
              title: const Text('换配色'),
              subtitle: Text(
                  c.paletteId == null ? '跟随全局' : paletteById(c.paletteId).name,
                  style: TextStyle(fontSize: 11, color: palette.fgWith(0.4))),
              onTap: () async {
                Navigator.pop(ctx);
                await _pickConvPalette(c);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline,
                  size: 20, color: Colors.redAccent),
              title: const Text('删除这个对话',
                  style: TextStyle(color: Colors.redAccent)),
              subtitle: Text('只删手机上的记录',
                  style: TextStyle(fontSize: 11, color: palette.fgWith(0.4))),
              onTap: () async {
                Navigator.pop(ctx);
                var cloud = false;
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (d) => StatefulBuilder(
                    builder: (d, setD) => AlertDialog(
                      title: Text('删除「${c.name}」？'),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('聊天记录会从手机移除。',
                              style: TextStyle(
                                  fontSize: 13, color: palette.fgWith(0.6))),
                          const SizedBox(height: 8),
                          CheckboxListTile(
                            value: cloud,
                            onChanged: (v) => setD(() => cloud = v ?? false),
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            title: const Text('同时删除云端记忆',
                                style: TextStyle(fontSize: 14)),
                            subtitle: Text('她将忘记这段对话里发生的事',
                                style: TextStyle(
                                    fontSize: 11, color: palette.fgWith(0.45))),
                          ),
                        ],
                      ),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(d, false),
                            child: const Text('取消')),
                        FilledButton(
                            onPressed: () => Navigator.pop(d, true),
                            child: const Text('删除')),
                      ],
                    ),
                  ),
                );
                if (ok != true) return;
                // 先从列表里拿掉，界面立刻响应
                if (mounted) {
                  setState(() {
                    _convs.removeWhere((e) => e.conv == c.conv);
                    _lastMsg.remove(c.conv);
                    _unread.remove(c.conv);
                  });
                }
                Haptics.medium();
                // 数据库操作放后台，不挡界面
                unawaited(_purgeConversation(c));
                if (cloud) {
                  try {
                    await ChatApi(
                            base: (await Settings.load()).base,
                            token: (await Settings.load()).token,
                            conv: c.conv)
                        .deleteSession(c.conv);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('已同时清除云端记忆')));
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('云端清理失败：$e')));
                    }
                  }
                }
                _refresh();
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 用当前接口和密钥拉一次模型列表，返回用户选中的模型名
  Future<String?> _fetchModels(
      String base, String key, Palette palette) async {
    var b = base.trim();
    while (b.endsWith('/')) {
      b = b.substring(0, b.length - 1);
    }
    if (b.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('先填接口地址')));
      }
      return null;
    }
    List<String> models = [];
    try {
      final resp = await http.get(
        Uri.parse('$b/models'),
        headers: {if (key.isNotEmpty) 'Authorization': 'Bearer $key'},
      ).timeout(const Duration(seconds: 12));
      if (resp.statusCode != 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('拉取失败：HTTP ${resp.statusCode}')));
        }
        return null;
      }
      final data = jsonDecode(utf8.decode(resp.bodyBytes));
      final list = (data is Map ? data['data'] : data) as List? ?? [];
      models = list
          .map((e) => (e is Map ? (e['id'] ?? '') : e).toString())
          .where((e) => e.isNotEmpty)
          .toList()
        ..sort();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('拉取失败：$e')));
      }
      return null;
    }
    if (models.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('这个接口没返回模型列表')));
      }
      return null;
    }
    if (!mounted) return null;
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
              child: Text('选一个模型（共 ${models.length} 个）',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: palette.accent)),
            ),
            for (final m in models)
              ListTile(
                dense: true,
                title: Text(m, style: const TextStyle(fontSize: 14)),
                onTap: () => Navigator.pop(ctx, m),
              ),
          ],
        ),
      ),
    );
  }
  Future<void> _createConversation() async {
    final palette = AppPrefs.instance.palette;
    final s = await Settings.load();
    final nameCtl = TextEditingController();

    var personas = List<Map<String, dynamic>>.from(_personas);
    var loading = personas.isEmpty;
    String? error;
    String? chosen =
        personas.isEmpty ? null : personas.first['persona_file'] as String?;
    var fetching = false;
    var useCustom = false;
    final baseCtl = TextEditingController();
    final keyCtl = TextEditingController();
    final modelCtl = TextEditingController();
    final noteCtl = TextEditingController();

    Future<void> fetch(StateSetter setSt) async {
      if (fetching) return;
      fetching = true;
      try {
        final api = ChatApi(base: s.base, token: s.token, conv: s.conv);
        final list = await api.listPersonas();
        final p = await SharedPreferences.getInstance();
        await p.setString('personas_cache', jsonEncode(list));
        if (!mounted) return;
        setState(() => _personas = list);
        setSt(() {
          personas = list;
          loading = false;
          error = null;
          chosen ??= list.isEmpty ? null : list.first['persona_file'] as String?;
        });
      } catch (e) {
        setSt(() {
          loading = false;
          error = personas.isEmpty ? e.toString() : null;
        });
      } finally {
        fetching = false;
      }
    }

    if (!mounted) return;
    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          if (loading) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) fetch(setSt);
            });
          }
          return Dialog(
            backgroundColor: palette.surface,
            insetPadding: const EdgeInsets.symmetric(horizontal: 28),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Text('新建对话',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: palette.fg)),
                      const Spacer(),
                      IconButton(
                        icon: Icon(Icons.close,
                            size: 20, color: palette.fgWith(0.5)),
                        onPressed: () => Navigator.pop(ctx, false),
                      ),
                    ],
                  ),
                  TextField(
                    controller: nameCtl,
                    autofocus: true,
                    style: TextStyle(color: palette.fg),
                    decoration: InputDecoration(
                      hintText: '给她起个称呼',
                      hintStyle: TextStyle(color: palette.fgWith(0.35)),
                      filled: true,
                      fillColor: palette.alt,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('使用其他模型的接口'),
                    subtitle: Text('填 OpenAI 兼容地址，直连，不经过你的服务器',
                        style: TextStyle(
                            fontSize: 11, color: palette.fgWith(0.45))),
                    value: useCustom,
                    onChanged: (v) => setSt(() => useCustom = v),
                  ),
                  if (useCustom) ...[
                    TextField(
                      controller: baseCtl,
                      style: TextStyle(fontSize: 13, color: palette.fg),
                      decoration: InputDecoration(
                        labelText: '接口地址',
                        hintText: 'https://api.openai.com/v1',
                        hintStyle: TextStyle(
                            fontSize: 12, color: palette.fgWith(0.3)),
                        filled: true,
                        fillColor: palette.alt,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: keyCtl,
                      style: TextStyle(fontSize: 13, color: palette.fg),
                      decoration: InputDecoration(
                        labelText: '密钥',
                        hintText: 'sk-...',
                        hintStyle: TextStyle(
                            fontSize: 12, color: palette.fgWith(0.3)),
                        filled: true,
                        fillColor: palette.alt,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: modelCtl,
                      style: TextStyle(fontSize: 13, color: palette.fg),
                      decoration: InputDecoration(
                        labelText: '模型名',
                        hintText: 'gpt-4o-mini',
                        hintStyle: TextStyle(
                            fontSize: 12, color: palette.fgWith(0.3)),
                        filled: true,
                        fillColor: palette.alt,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        suffixIcon: IconButton(
                          tooltip: '拉取模型列表',
                          icon: const Icon(Icons.refresh, size: 18),
                          onPressed: () async {
                            final picked = await _fetchModels(
                              baseCtl.text.trim(),
                              keyCtl.text.trim(),
                              palette,
                            );
                            if (picked != null) {
                              setSt(() => modelCtl.text = picked);
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: noteCtl,
                      maxLines: 3,
                      minLines: 2,
                      style: TextStyle(fontSize: 13, color: palette.fg),
                      decoration: InputDecoration(
                        labelText: '人设（可选）',
                        hintText: '例如：你是话很少的猫，句子短，爱答不理但心软',
                        hintStyle: TextStyle(
                            fontSize: 12, color: palette.fgWith(0.3)),
                        filled: true,
                        fillColor: palette.alt,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  if (!useCustom) ...[
                  Text('选择人格',
                      style: TextStyle(
                          fontSize: 12, color: palette.fgWith(0.5))),
                  const SizedBox(height: 8),
                  if (loading)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Row(
                        children: [
                          const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2)),
                          const SizedBox(width: 10),
                          Text('正在读取人格…',
                              style: TextStyle(
                                  fontSize: 12, color: palette.fgWith(0.5))),
                        ],
                      ),
                    )
                  else if (error != null)
                    Text('读取人格失败：$error',
                        style: const TextStyle(
                            fontSize: 11, color: Colors.redAccent))
                  else if (personas.isEmpty)
                    Text('服务器上没有可用人格',
                        style: TextStyle(
                            fontSize: 12, color: palette.fgWith(0.5)))
                  else
                    Container(
                      constraints: const BoxConstraints(maxHeight: 260),
                      decoration: BoxDecoration(
                        color: palette.alt,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListView.builder(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: personas.length,
                        itemBuilder: (c, i) {
                          final p = personas[i];
                          final pf = p['persona_file'] as String?;
                          final selected = pf == chosen;
                          return InkWell(
                            onTap: () => setSt(() => chosen = pf),
                            borderRadius: BorderRadius.circular(10),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              child: Row(
                                children: [
                                  Icon(
                                    selected
                                        ? Icons.radio_button_checked
                                        : Icons.radio_button_off,
                                    size: 20,
                                    color: selected
                                        ? palette.accent
                                        : palette.fgWith(0.35),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      (p['name'] ?? '') as String,
                                      style: TextStyle(
                                        fontSize: 15,
                                        color: palette.fg,
                                        fontWeight: selected
                                            ? FontWeight.w600
                                            : FontWeight.w400,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('取消'),
                      ),
                      const Spacer(),
                      FilledButton(
                        onPressed: (chosen == null && !useCustom)
                            ? null
                            : () => Navigator.pop(ctx, true),
                        child: const Text('创建'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (created != true || chosen == null) return;

    final name = nameCtl.text.trim().isEmpty ? '新对话' : nameCtl.text.trim();

    // 自定义接口：本地建会话，不经过服务器
    if (useCustom) {
      final base = baseCtl.text.trim();
      final model = modelCtl.text.trim();
      if (base.isEmpty || model.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('接口地址和模型名不能为空')));
        }
        return;
      }
      final c = Conversation(
        conv: 'local_${DateTime.now().millisecondsSinceEpoch}',
        name: name,
        createdAt: DateTime.now(),
        sortOrder: await HistoryDb.convNextSort(),
        apiBase: base,
        apiKey: keyCtl.text.trim(),
        model: model,
        systemNote: noteCtl.text.trim().isEmpty ? null : noteCtl.text.trim(),
      );
      await HistoryDb.convUpsert(c);
      await _refresh();
      if (!mounted) return;
      await _openChat(c);
      return;
    }

    try {
      final res = await ChatApi(base: s.base, token: s.token, conv: s.conv)
          .createSession(name, chosen!);
      final convId = (res['conv_id'] ?? '') as String;
      if (convId.isEmpty) throw ChatError('服务器没有返回会话 ID');
      final personaLabel = personas.firstWhere(
        (p) => p['persona_file'] == chosen,
        orElse: () => <String, dynamic>{},
      )['name'] as String?;
      final c = Conversation(
        conv: convId,
        name: name,
        persona: chosen,
        createdAt: DateTime.now(),
        sortOrder: await HistoryDb.convNextSort(),
      );
      await HistoryDb.convUpsert(c);
      if (!mounted) return;
      await _openChat(c, personaLabel: personaLabel);
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      final msg = '$e'.contains('Handshake')
          ? '连接被中断了（多半是 VPN 或网络抖动），已重试 3 次。\n试着关掉 VPN 再点一次。'
          : '创建失败：$e';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _pickConvImage(Conversation c, {required bool avatar}) async {
    final picked = await ImagePicker().pickImage(
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
    if (avatar) {
      c.avatarPath = stored;
    } else {
      c.bgPath = stored;
    }
    await HistoryDb.convUpsert(c);
    _refresh();
  }

  Future<void> _pickConvPalette(Conversation c) async {
    final cur = AppPrefs.instance.palette;
    final picked = await showModalBottomSheet<String?>(
      context: context,
      backgroundColor: cur.surface,
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
              subtitle: Text('单独设背景色 / 主色 / 双方气泡色',
                  style: TextStyle(fontSize: 11, color: cur.fgWith(0.45))),
              onTap: () => Navigator.pop(ctx, '__custom__'),
            ),
            ListTile(
              leading: const Icon(Icons.settings_backup_restore, size: 20),
              title: const Text('跟随全局'),
              trailing: c.paletteId == null
                  ? Icon(Icons.check, size: 18, color: cur.accent)
                  : null,
              onTap: () => Navigator.pop(ctx, '__global__'),
            ),
            for (final p in kPalettes)
              ListTile(
                leading: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [p.accent, p.bubbleMine]),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                title: Text(p.name),
                trailing: c.paletteId == p.id
                    ? Icon(Icons.check, size: 18, color: cur.accent)
                    : null,
                onTap: () => Navigator.pop(ctx, p.id),
              ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    if (picked == '__custom__') {
      await _editConvColors(c);
      return;
    }
    c.paletteId = picked == '__global__' ? null : picked;
    c.customColors = null;
    await HistoryDb.convUpsert(c);
    _refresh();
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

  /// 单独给某个会话调 4 个颜色
  Future<void> _editConvColors(Conversation c) async {
    final base = AppPrefs.instance.palette;
    var colors = <String, String>{
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

    final labels = {
      'bg': '背景色',
      'accent': '主题色',
      'mine': '我的气泡',
      'other': '她的气泡',
    };

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('自定义配色'),
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
                      border: Border.all(
                          color: base.fgWith(0.2), width: 1),
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
                    if (picked != null) {
                      setD(() => colors[k] = _hex(picked));
                    }
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
    await HistoryDb.convUpsert(c);
    _refresh();
  }

  Future<void> _pickHomePalette() async {
    final prefs = AppPrefs.instance;
    final cur = prefs.palette;
    final picked = await showModalBottomSheet<String?>(
      context: context,
      backgroundColor: cur.surface,
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
              onTap: () => Navigator.pop(ctx, 'custom'),
            ),
            ListTile(
              leading: const Icon(Icons.settings_backup_restore, size: 20),
              title: const Text('跟随全局'),
              trailing: prefs.homePaletteId == null
                  ? Icon(Icons.check, size: 18, color: cur.accent)
                  : null,
              onTap: () => Navigator.pop(ctx, 'global'),
            ),
            for (final p in kPalettes)
              ListTile(
                leading: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [p.accent, p.bubbleMine]),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                title: Text(p.name),
                trailing: prefs.homePaletteId == p.id
                    ? Icon(Icons.check, size: 18, color: cur.accent)
                    : null,
                onTap: () => Navigator.pop(ctx, p.id),
              ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    if (picked == 'custom') {
      final ok = await _editGlobalCustomColors();
      if (ok) await prefs.setPalette('custom');
      return;
    }
    await prefs.setHomePalette(picked);
  }

  /// 全局自定义四色
  Future<bool> _editGlobalCustomColors() async {
    final prefs = AppPrefs.instance;
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
    final base = prefs.palette;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('自定义颜色'),
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
                      border: Border.all(color: base.fgWith(0.2)),
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
    if (ok != true) return false;
    await prefs.setCustomBg(values['bg']!.toARGB32());
    await prefs.setCustomAccent(values['accent']!.toARGB32());
    await prefs.setCustomMine(values['mine']!.toARGB32());
    await prefs.setCustomOther(values['other']!.toARGB32());
    return true;
  }

  Widget _homeDrawer(Palette palette) {
    return Drawer(
      width: MediaQuery.of(context).size.width * 0.55,
      backgroundColor: palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(18),
          bottomRight: Radius.circular(18),
        ),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(AppConfig.brand,
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: palette.fg)),
                  const SizedBox(height: 2),
                  Text('主菜单',
                      style: TextStyle(
                          fontSize: 11, color: palette.fgWith(0.4))),
                ],
              ),
            ),
            const Divider(height: 1),
            const SizedBox(height: 8),
            ListTile(
              leading: Icon(Icons.photo_library_outlined,
                  color: palette.accent, size: 22),
              title: const Text('相册'),
              onTap: () async {
                Navigator.pop(context);
                await Navigator.of(context).push(
                  themedRoute(palette, const AlbumPage()),
                );
                // 相册里可能改了某个会话的头像/背景，回来要重读
                if (mounted) await _refresh();
              },
            ),

            ListTile(
              leading: Icon(Icons.settings_outlined,
                  color: palette.accent, size: 22),
              title: const Text('设置'),
              onTap: () async {
                Navigator.pop(context);
                await Navigator.of(context).push(
                  themedRoute(palette, const SettingsPage()),
                );
                if (mounted) _refresh();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _tileAvatar(Conversation c, Palette palette) {
    final f = (c.avatarPath != null && File(c.avatarPath!).existsSync())
        ? File(c.avatarPath!)
        : null;
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [palette.accent, palette.accent.withValues(alpha: 0.55)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        image: f != null
            ? DecorationImage(image: FileImage(f), fit: BoxFit.cover)
            : null,
      ),
      child: f == null
          ? const Icon(Icons.set_meal, color: Colors.white, size: 26)
          : null,
    );
  }

  Widget _tile({
    Key? key,
    required Palette palette,
    required Conversation conv,
    required String preview,
    required String time,
    required int badge,
    required VoidCallback onTap,
    required VoidCallback onMenu,
  }) {
    final light = palette.isLight;
    final cardBase = Color.lerp(palette.surface, palette.accent, 0.10)!;
    final cardColor = Color.lerp(cardBase, palette.bg, 0.18)!;

    return Padding(
      key: key,
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: cardColor.withValues(alpha: light ? 0.95 : 0.88),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: palette.accent.withValues(alpha: 0.22),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: light ? 0.08 : 0.35),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                _tileAvatar(conv, palette),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(conv.name,
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w600)),
                          const Spacer(),
                          Text(time,
                              style: TextStyle(
                                  fontSize: 11, color: palette.fgWith(0.3))),
                          // 长按已用于拖动排序，菜单挪到这个按钮
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: onMenu,
                            child: Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: Icon(Icons.more_horiz,
                                  size: 18, color: palette.fgWith(0.45)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              preview,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 13, color: palette.fgWith(0.4)),
                            ),
                          ),
                          if (badge > 0)
                            Container(
                              margin: const EdgeInsets.only(left: 8),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              constraints: const BoxConstraints(minWidth: 18),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE5484D),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                badge > 99 ? '99+' : '$badge',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    fontSize: 10, color: Colors.white),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
