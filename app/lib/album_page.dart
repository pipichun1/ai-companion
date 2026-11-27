import 'dart:io';

import 'package:flutter/material.dart';

import 'package:image_picker/image_picker.dart';

import 'crop_page.dart';
import 'haptics.dart';
import 'history_db.dart';
import 'prefs.dart';
import 'theme.dart';

/// 相册：只收手动存进来的图
class AlbumPage extends StatefulWidget {
  const AlbumPage({super.key});

  @override
  State<AlbumPage> createState() => _AlbumPageState();
}

class _AlbumPageState extends State<AlbumPage> {
  List<AlbumItem> _items = [];
  String _filter = 'all';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await HistoryDb.albumList();
    if (!mounted) return;
    setState(() {
      _items = items.where((e) => File(e.path).existsSync()).toList();
      _loading = false;
    });
  }

  Future<void> _upload() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 2560,
      maxHeight: 2560,
      imageQuality: 92,
    );
    if (picked == null) return;
    final stored = await copyToAppDir(File(picked.path), prefix: 'album');
    await HistoryDb.albumAdd(AlbumItem(
      path: stored,
      createdAt: DateTime.now(),
      source: 'upload',
    ));
    await _load();
  }

  String _monthLabel(DateTime t) => '${t.year} 年 ${t.month} 月';

  List<AlbumItem> get _shown {
    if (_filter == 'all') return _items;
    return _items.where((e) => (e.source ?? '') == _filter).toList();
  }

  Widget _filterBar(Palette palette) {
    const tabs = [
      ['all', '全部'],
      ['me', '我存的'],
      ['her', '她发的'],
      ['upload', '上传'],
    ];
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (final t in tabs)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(t[1]),
                selected: _filter == t[0],
                onSelected: (_) => setState(() => _filter = t[0]),
                labelStyle: TextStyle(
                  fontSize: 12,
                  color: _filter == t[0] ? Colors.white : palette.fgWith(0.6),
                ),
                selectedColor: palette.accent,
                backgroundColor: palette.alt,
                side: BorderSide.none,
                showCheckmark: false,
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPrefs.instance.palette;
    return Scaffold(
      appBar: AppBar(
        title: const Text('相册'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text('${_items.length} 张',
                  style: TextStyle(
                      fontSize: 12, color: palette.fgWith(0.45))),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? _empty(palette)
              : Column(
                  children: [
                    _filterBar(palette),
                    Expanded(child: _grid(palette)),
                  ],
                ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: palette.accent,
        foregroundColor: Colors.white,
        onPressed: _upload,
        icon: const Icon(Icons.add_photo_alternate_outlined),
        label: const Text('上传'),
      ),
    );
  }

  Widget _empty(Palette palette) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.photo_library_outlined,
              size: 48, color: palette.fgWith(0.2)),
          const SizedBox(height: 12),
          Text('相册还是空的',
              style: TextStyle(color: palette.fgWith(0.45), fontSize: 14)),
          const SizedBox(height: 6),
          Text('在聊天里长按一张图，选择「存到相册」',
              style: TextStyle(color: palette.fgWith(0.3), fontSize: 12)),
        ],
      ),
    );
  }

  Widget _grid(Palette palette) {
    // 按月分组后铺成一条列表，组内三列
    final children = <Widget>[];
    String? lastMonth;
    final list = _shown;
    for (var i = 0; i < list.length; i++) {
      final item = list[i];
      final month = _monthLabel(item.createdAt);
      if (month != lastMonth) {
        lastMonth = month;
        children.add(Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
          child: Text(month,
              style: TextStyle(
                  fontSize: 12,
                  color: palette.fgWith(0.45),
                  fontWeight: FontWeight.w600)),
        ));
        // 收集本月所有图片
        final monthItems = <AlbumItem>[];
        for (var j = i; j < _items.length; j++) {
          if (_monthLabel(_items[j].createdAt) != month) break;
          monthItems.add(_items[j]);
        }
        children.add(GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
          ),
          itemCount: monthItems.length,
          itemBuilder: (c, k) => _cell(monthItems[k], palette),
        ));
        i += monthItems.length - 1;
      }
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      children: children,
    );
  }

  Widget _cell(AlbumItem item, Palette palette) {
    return GestureDetector(
      onTap: () => _view(item, palette),
      onLongPress: () {
        Haptics.medium();
        _menu(item, palette);
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(
          File(item.path),
          fit: BoxFit.cover,
          cacheWidth: 300,
          errorBuilder: (c, e, s) => Container(
            color: palette.alt,
            child: Icon(Icons.broken_image_outlined,
                color: palette.fgWith(0.3)),
          ),
        ),
      ),
    );
  }

  void _view(AlbumItem item, Palette palette) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              Positioned.fill(
                child: InteractiveViewer(
                  minScale: 0.4,
                  maxScale: 6,
                  boundaryMargin: const EdgeInsets.all(120),
                  child: Center(
                    child: Image.file(File(item.path), fit: BoxFit.contain),
                  ),
                ),
              ),
              SafeArea(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text(text), duration: const Duration(seconds: 1)));
  }

  /// 选一个会话，把这张图设为它的头像或背景
  Future<void> _applyToConversation(AlbumItem item,
      {required bool avatar}) async {
    final convs = await HistoryDb.convList();
    if (!mounted) return;
    if (convs.isEmpty) {
      _toast('还没有会话');
      return;
    }
    final palette = AppPrefs.instance.palette;
    final picked = await showModalBottomSheet<Conversation>(
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
              child: Text(avatar ? '设为谁的头像？' : '设为哪个会话的背景？',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: palette.accent)),
            ),
            for (final c in convs)
              ListTile(
                leading: CircleAvatar(
                  radius: 16,
                  backgroundColor: palette.alt,
                  backgroundImage: (c.avatarPath != null &&
                          File(c.avatarPath!).existsSync())
                      ? FileImage(File(c.avatarPath!))
                      : null,
                  child: (c.avatarPath != null &&
                          File(c.avatarPath!).existsSync())
                      ? null
                      : Icon(Icons.set_meal,
                          size: 16, color: palette.fgWith(0.4)),
                ),
                title: Text(c.name),
                onTap: () => Navigator.pop(ctx, c),
              ),
          ],
        ),
      ),
    );
    if (picked == null) return;

    // 先裁剪，再复制一份（删相册图也不会弄坏外观）
    final size = MediaQuery.of(context).size;
    final cropped = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => CropPage(
          file: File(item.path),
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
      picked.avatarPath = stored;
    } else {
      picked.bgPath = stored;
    }
    try {
      await HistoryDb.convUpsert(picked);
      _toast(avatar ? '已设为「${picked.name}」的头像' : '已设为「${picked.name}」的背景');
    } catch (e) {
      _toast('保存失败：$e');
    }
  }
  void _menu(AlbumItem item, Palette palette) {
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
              leading: const Icon(Icons.wallpaper, size: 20),
              title: const Text('设为某个会话的背景'),
              subtitle: Text('会先让你选是哪个会话',
                  style: TextStyle(fontSize: 11, color: palette.fgWith(0.4))),
              onTap: () async {
                Navigator.pop(ctx);
                await _applyToConversation(item, avatar: false);
              },
            ),
            ListTile(
              leading: const Icon(Icons.face_retouching_natural, size: 20),
              title: const Text('设为某个会话的头像'),
              subtitle: Text('会先让你选是哪个会话',
                  style: TextStyle(fontSize: 11, color: palette.fgWith(0.4))),
              onTap: () async {
                Navigator.pop(ctx);
                await _applyToConversation(item, avatar: true);
              },
            ),
            ListTile(
              leading: const Icon(Icons.view_list, size: 20),
              title: const Text('设为主页背景'),
              onTap: () async {
                Navigator.pop(ctx);
                await AppPrefs.instance.setHomeBg(item.path);
                _toast('主页背景已更新');
              },
            ),
            ListTile(
              leading: const Icon(Icons.person_outline, size: 20),
              title: const Text('设为我的头像'),
              onTap: () async {
                Navigator.pop(ctx);
                await AppPrefs.instance.setMyAvatar(item.path);
                if (mounted) setState(() {});
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline,
                  size: 20, color: Colors.redAccent),
              title:
                  const Text('从相册删除', style: TextStyle(color: Colors.redAccent)),
              onTap: () async {
                Navigator.pop(ctx);
                await HistoryDb.albumRemove(item.id!);
                final f = File(item.path);
                if (await f.exists()) await f.delete();
                if (mounted) {
                  setState(() => _items.remove(item));
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
