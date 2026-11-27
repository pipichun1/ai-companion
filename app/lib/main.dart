import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'app_config.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'album_page.dart';
import 'chat_api.dart';
import 'color_picker.dart';
import 'haptics.dart';
import 'history_db.dart';
import 'home_page.dart';
import 'img_util.dart';
import 'prefs.dart';
import 'settings_page.dart';
import 'self_actions.dart';
import 'settings_store.dart';
import 'theme.dart';
import 'themed_route.dart';

final GlobalKey<NavigatorState> appNavigatorKey =
    GlobalKey<NavigatorState>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(const DaFeiYuApp());
}

class DaFeiYuApp extends StatefulWidget {
  const DaFeiYuApp({super.key});

  @override
  State<DaFeiYuApp> createState() => _DaFeiYuAppState();
}

class _DaFeiYuAppState extends State<DaFeiYuApp> {
  @override
  void initState() {
    super.initState();
    AppPrefs.instance.load();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppPrefs.instance,
      builder: (context, _) {
        final palette = AppPrefs.instance.palette;
        return MaterialApp(
          navigatorKey: appNavigatorKey,
          title: AppConfig.brand,
          debugShowCheckedModeBanner: false,
          theme: buildTheme(palette),
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (context, child) {
            final style = SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness:
                  palette.isLight ? Brightness.dark : Brightness.light,
              systemNavigationBarColor: Colors.transparent,
              systemNavigationBarDividerColor: Colors.transparent,
              systemNavigationBarContrastEnforced: false,
              systemNavigationBarIconBrightness:
                  palette.isLight ? Brightness.dark : Brightness.light,
            );
            return AnnotatedRegion<SystemUiOverlayStyle>(
              value: style,
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: const MessagesHome(),
        );
      },
    );
  }
}

/// 全局顶部提示：全 App 只有一条，避免多页面各画一份
class ToastBar {
  ToastBar._();

  static OverlayEntry? _entry;
  static String _last = '';
  static DateTime _at = DateTime.fromMillisecondsSinceEpoch(0);

  static void show(String text) {
    final now = DateTime.now();
    if (text == _last && now.difference(_at).inMilliseconds < 800) return;
    _last = text;
    _at = now;

    final overlay = appNavigatorKey.currentState?.overlay;
    if (overlay == null) return;

    _entry?.remove();
    _entry = null;

    final palette = AppPrefs.instance.palette;
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => Positioned(
        top: MediaQuery.of(ctx).padding.top + 64,
        left: 0,
        right: 0,
        child: IgnorePointer(
          child: Center(
            child: _TopToast(
              text: text,
              palette: palette,
              onDone: () {
                entry.remove();
                if (_entry == entry) _entry = null;
              },
            ),
          ),
        ),
      ),
    );
    overlay.insert(entry);
    _entry = entry;
  }
}

/// 顶部提示浮条：下滑淡入 → 停留 → 上滑淡出
class _TopToast extends StatefulWidget {
  const _TopToast({
    required this.text,
    required this.palette,
    required this.onDone,
  });

  final String text;
  final Palette palette;
  final VoidCallback onDone;

  @override
  State<_TopToast> createState() => _TopToastState();
}

class _TopToastState extends State<_TopToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  Timer? _hold;

  @override
  void initState() {
    super.initState();
    _c.addStatusListener((st) {
      if (st == AnimationStatus.completed) {
        _hold = Timer(const Duration(milliseconds: 900), () async {
          if (!mounted) return;
          await _c.reverse();
          if (mounted) widget.onDone();
        });
      }
    });
    _c.forward();
  }

  @override
  void dispose() {
    _hold?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        // 进：0→0.25，停：0.25→0.8，出：0.8→1
        final t = _c.value;
        double progress;
        if (t <= 0.25) {
          progress = Curves.easeOutBack.transform(t / 0.25);
        } else if (t >= 0.8) {
          progress = 1 - Curves.easeInCubic.transform((t - 0.8) / 0.2);
        } else {
          progress = 1;
        }
        return Opacity(
          opacity: progress.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, -14 * (1 - progress)),
            child: Transform.scale(
              scale: 0.94 + 0.06 * progress,
              child: child,
            ),
          ),
        );
      },
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: p.surface.withValues(alpha: 0.97),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: p.accent.withValues(alpha: 0.28)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Text(widget.text,
              style: TextStyle(fontSize: 13, color: p.fg)),
        ),
      ),
    );
  }
}

/// 气泡弹出动画：缩放 + 淡入
class _PopBubble extends StatefulWidget {
  const _PopBubble({
    super.key,
    required this.child,
    required this.animate,
    required this.align,
  });

  final Widget child;
  final bool animate;
  final Alignment align;

  @override
  State<_PopBubble> createState() => _PopBubbleState();
}

class _PopBubbleState extends State<_PopBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
    value: widget.animate ? 0 : 1,
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) _c.forward(from: 0);
  }

  @override
  void didUpdateWidget(covariant _PopBubble old) {
    super.didUpdateWidget(old);
    if (widget.animate && !old.animate) {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = Curves.easeOutBack.transform(_c.value);
        final fade = _c.value.clamp(0.0, 1.0);
        final scale = 0.68 + 0.32 * t;
        final dy = 10 * (1 - _c.value);
        return Opacity(
          opacity: fade,
          child: Transform.translate(
            offset: Offset(0, dy),
            child: Transform.scale(
              scale: scale,
              alignment: widget.align,
              child: child,
            ),
          ),
        );
      },
      child: widget.child,
    );
  }
}

class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key,
    required this.conv,
    required this.name,
    this.personaName,
    this.avatarPath,
    this.bgPath,
    this.paletteId,
    this.customColors,
    this.apiBase,
    this.apiKey,
    this.model,
    this.systemNote,
    this.highlightId,
  });

  final String conv;
  final String name;
  final String? personaName;
  final String? avatarPath;
  final String? bgPath;
  final String? paletteId;
  final String? customColors;

  /// 自带接口（非空则直连该地址，不走自家桥）
  final String? apiBase;
  final String? apiKey;
  final String? model;
  final String? systemNote;
  final int? highlightId;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage>
    with SingleTickerProviderStateMixin {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<Msg> _msgs = [];
  final _picker = ImagePicker();
  final Map<int, GlobalKey> _msgKeys = {};

  Settings? _settings;
  bool _sending = false;
  bool _ready = false;
  bool _loadingMore = false;
  File? _pendingImage;
  Msg? _quoted;
  int? _highlightId;
  bool _offline = false;
  double _dragDx = 0;
  int _menuSession = 0;
  int _lastMenuState = -1;
  String? _doneAction;
  DateTime _copyLock = DateTime.fromMillisecondsSinceEpoch(0);
  String? _bgPath;
  String? _avatarPath;
  String? _paletteId;
  String? _customColors;

  final Set<Object> _poppedIds = {};
  late final AnimationController _blink = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _scroll.addListener(_onScrollHistory);
    _input.addListener(_saveDraft);
    // 进页面就先带上这个会话的外观，不然会显示默认
    _avatarPath = widget.avatarPath;
    _bgPath = widget.bgPath;
    _paletteId = widget.paletteId;
    _customColors = widget.customColors;
    _boot();
  }

  Timer? _draftTimer;

  Future<void> _saveDraft() async {
    _draftTimer?.cancel();
    final conv = _settings == null ? null : widget.conv;
    if (conv == null) return;
    final text = _input.text;
    _draftTimer = Timer(const Duration(milliseconds: 400), () async {
      final p = await SharedPreferences.getInstance();
      if (text.isEmpty) {
        await p.remove('draft_$conv');
      } else {
        await p.setString('draft_$conv', text);
      }
    });
  }

  Future<void> _restoreDraft(String conv) async {
    final p = await SharedPreferences.getInstance();
    final draft = p.getString('draft_$conv');
    if (draft != null && draft.isNotEmpty && mounted) {
      _input.text = draft;
      _input.selection =
          TextSelection.collapsed(offset: _input.text.length);
    }
  }

  @override
  void dispose() {
    _toastEntry?.remove();
    _blink.dispose();
    _scroll.dispose();
    _input.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!mounted || !_scroll.hasClients) return;
    final pos = _scroll.position;
    if (_loadingMore) return;
    if (pos.pixels >= pos.maxScrollExtent - 60 && _msgs.isNotEmpty) {
      _loadOlder();
    }
  }

  /// 从设置页回来时，重新读一次这个会话的外观
  Future<void> _reloadAppearance() async {
    final c = await HistoryDb.convGet(widget.conv);
    if (c == null || !mounted) return;
    setState(() {
      _avatarPath = c.avatarPath;
      _bgPath = c.bgPath;
      _paletteId = c.paletteId;
      _customColors = c.customColors;
    });
  }

  Future<void> _boot() async {
    final s = await Settings.load();
    var history = await HistoryDb.recent(widget.conv);

    // 从搜索进来时，往前多翻几页，直到找到目标消息
    final target = widget.highlightId;
    if (target != null) {
      var rounds = 0;
      while (!history.any((m) => m.id == target) &&
          history.isNotEmpty &&
          rounds < 12) {
        final older = await HistoryDb.before(
            widget.conv, history.first.time.millisecondsSinceEpoch);
        if (older.isEmpty) break;
        history = [...older, ...history];
        rounds++;
      }
    }

    if (!mounted) return;
    setState(() {
      _settings = s;
      _msgs
        ..clear()
        ..addAll(history);
      _ready = true;
      if (target != null) _highlightId = target;
    });
    await _restoreDraft(widget.conv);

    if (target != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToId(target));
    } else {
      _scrollToBottom(jump: true);
    }
  }

  void _jumpToId(int id) {
    final ctx = _msgKeys[id]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx,
          duration: const Duration(milliseconds: 300), alignment: 0.35);
    }
    _blink.repeat(reverse: true);
    Future.delayed(const Duration(seconds: 4), () {
      _blink.stop();
      if (mounted) setState(() => _highlightId = null);
    });
  }

  Future<void> _loadOlder() async {
    if (_msgs.isEmpty || _settings == null) return;
    setState(() => _loadingMore = true);
    final oldest = _msgs.first.time.millisecondsSinceEpoch;
    final older = await HistoryDb.before(widget.conv, oldest);
    if (!mounted) return;
    setState(() {
      _msgs.insertAll(0, older);
      _loadingMore = false;
    });
  }

  /// 列表是反向的：offset 0 即最新
  double _lastOffset = 0;

  /// 往上翻历史时收起键盘
  void _onScrollHistory() {
    if (!_scroll.hasClients) return;
    final offset = _scroll.offset;
    final delta = offset - _lastOffset;
    _lastOffset = offset;

    // 反向列表：offset 变大 = 往历史翻；正向列表：offset 变小 = 往历史翻
    final reversed = _msgs.length > 12;
    final towardHistory = reversed ? delta > 6 : delta < -6;
    if (!towardHistory) return;

    final focus = FocusScope.of(context);
    if (focus.hasFocus) focus.unfocus();
  }

  void _scrollToBottom({bool jump = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final target =
          _msgs.length > 12 ? 0.0 : _scroll.position.maxScrollExtent;
      if (jump) {
        _scroll.jumpTo(target);
      } else {
        _scroll.animateTo(target,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut);
      }
    });
  }

  Msg? _findById(int? id) {
    if (id == null) return null;
    for (final m in _msgs) {
      if (m.id == id) return m;
    }
    return null;
  }

  String _clip(String text) {
    final t = text.replaceAll('\n', ' ').trim();
    return t.length > 30 ? '${t.substring(0, 30)}…' : t;
  }

  OverlayEntry? _toastEntry;

  /// 顶部小浮条（全局唯一）
  void _toast(String text) {
    _toastEntry?.remove();
    _toastEntry = null;
    ToastBar.show(text);
  }
  /// 执行她的小动作：一天一次，只换当前会话
  Future<bool> _runSelfAction(SelfAction act) async {
    if (await dressedToday(widget.conv)) return false;
    final path = await applySelfAction(conv: widget.conv, action: act);
    if (path == null) return false;
    await markDressed(widget.conv);
    if (mounted) {
      setState(() {
        if (act.kind == 'avatar') {
          _avatarPath = path;
        } else {
          _bgPath = path;
        }
      });
    }
    Haptics.light();
    return true;
  }
  Future<void> _copyText(Msg m) async {
    await Clipboard.setData(ClipboardData(text: m.text));
    Haptics.light();
    if (mounted) _toast('已复制');
  }

  void _startQuote(Msg m) {
    setState(() => _quoted = m);
    _scrollToBottom();
  }

  String _quoteTextOf(Msg m) {
    final t = m.quoteText;
    if (t != null && t.trim().isNotEmpty) return _clip(t);
    if (m.imagePath != null) return '[图片]';
    return '（无文字）';
  }

  String _quotePreview(Msg? m) {
    if (m == null) return '';
    if (m.text.trim().isNotEmpty) return _clip(m.text);
    if (m.imagePath != null) return '[图片]';
    return '（内容为空）';
  }

  Future<void> _deleteMsg(Msg m) async {
    if (m.id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这条消息？'),
        content: const Text('只从手机本地删除，服务端的记忆不受影响。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    await HistoryDb.deleteOne(m.id!);
    if (!mounted) return;
    setState(() => _msgs.remove(m));
    Haptics.light();
    _toast('已删除');
  }

  void _jumpTo(Msg? target) {
    final id = target?.id;
    if (id == null) return;
    final ctx = _msgKeys[id]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx,
          duration: const Duration(milliseconds: 250), alignment: 0.4);
    } else {
      _toast('原消息在更早的位置，往上翻一下');
    }
  }

  void _showMenu(Msg m) {
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
              leading: const Icon(Icons.copy, size: 20),
              title: const Text('复制全文'),
              onTap: () {
                Navigator.pop(ctx);
                _copyText(m);
              },
            ),

            ListTile(
              leading: const Icon(Icons.format_quote, size: 20),
              title: const Text('引用'),
              onTap: () {
                Navigator.pop(ctx);
                _startQuote(m);
              },
            ),
            if (m.imagePath != null)
              ListTile(
                leading: const Icon(Icons.photo_library_outlined, size: 20),
                title: const Text('存到相册'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _saveToAlbum(m);
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline,
                  size: 20, color: Colors.redAccent),
              title:
                  const Text('删除', style: TextStyle(color: Colors.redAccent)),
              onTap: () {
                Navigator.pop(ctx);
                _deleteMsg(m);
              },
            ),
          ],
        ),
      ),
    );
  }

  bool _isNetworkError(Object e) {
    final t = e.toString();
    return t.contains('SocketException') ||
        t.contains('Failed host lookup') ||
        t.contains('TimeoutException') ||
        t.contains('ClientException') ||
        t.contains('Connection');
  }

  Future<void> _saveToAlbum(Msg m) async {
    final path = m.imagePath;
    if (path == null) return;
    final src = File(path);
    if (!await src.exists()) {
      _toast('图片文件已丢失');
      return;
    }
    if (await HistoryDb.albumHas(path)) {
      _toast('已经在相册里了');
      return;
    }
    final stored = await copyToAppDir(src, prefix: 'album');
    await HistoryDb.albumAdd(AlbumItem(
      path: stored,
      createdAt: DateTime.now(),
      source: m.mine ? 'me' : 'her',
      msgId: m.id,
    ));
    Haptics.light();
    _toast('已存到相册');
  }

  Future<void> _pickImage() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1280,
      maxHeight: 1280,
      imageQuality: 70,
    );
    if (picked == null) return;
    final f = File(picked.path);
    final size = await f.length();
    if (size > 2 * 1024 * 1024) {
      if (!mounted) return;
      _toast('这张图太大了（超过 2MB），换一张小一点的');
      return;
    }
    setState(() => _pendingImage = f);
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    final img = _pendingImage;
    if ((text.isEmpty && img == null) || _sending) return;
    _input.clear();
    setState(() => _pendingImage = null);

    String? storedPath;
    if (img != null) storedPath = await copyToAppDir(img);
    final quoted = _quoted;
    setState(() => _quoted = null);
    await _sendMessage(text, imagePath: storedPath, quoted: quoted);
  }

  Future<void> _sendMessage(String text,
      {String? imagePath, Msg? quoted}) async {
    final s = _settings;
    if (s == null || _sending) return;

    final userMsg = Msg(
      text: text,
      mine: true,
      time: DateTime.now(),
      imagePath: imagePath,
      quoteText: quoted?.text,
      quoteMsgId: quoted?.id,
    );
    await HistoryDb.insert(widget.conv, userMsg);

    final reply = Msg(
      text: '',
      mine: false,
      time: DateTime.now(),
      status: MsgStatus.pending,
      retryText: text,
      imagePath: imagePath,
    );
    await HistoryDb.insert(widget.conv, reply);

    if (!mounted) return;
    setState(() {
      _msgs.add(userMsg);
      _msgs.add(reply);
      _sending = true;
    });
    _scrollToBottom();

    final payload = quoted == null
        ? text
        : '（引用${quoted.mine ? "我" : "你"}刚才的话：「${_quoteTextOf(quoted)}」）\n$text';
    await _request(s, payload, imagePath, reply);

    if (mounted) setState(() => _sending = false);
    _scrollToBottom();
  }

  Future<void> _retry(Msg failed) async {
    if (_sending || _settings == null) return;
    setState(() {
      failed.text = '';
      failed.status = MsgStatus.pending;
      _sending = true;
    });
    await _request(_settings!, failed.retryText ?? '', failed.imagePath, failed);
    if (mounted) setState(() => _sending = false);
    _scrollToBottom();
  }

  Future<void> _request(
      Settings s, String text, String? imagePath, Msg reply,
      {int attempt = 0}) async {
    final direct = widget.apiBase != null && widget.apiBase!.isNotEmpty;
    final api = ChatApi(
      base: direct ? widget.apiBase! : s.base,
      token: direct ? (widget.apiKey ?? '') : s.token,
      conv: widget.conv,
      model: direct ? widget.model : null,
      systemNote: direct
          ? [
              if (widget.systemNote != null &&
                  widget.systemNote!.trim().isNotEmpty)
                widget.systemNote!.trim(),
              kAbilitiesNote,
            ].join('\n\n')
          : null,
      direct: direct,
    );
    try {
      String? b64;
      if (imagePath != null) {
        var f = File(imagePath);
        if (await f.exists()) {
          f = await compressForUpload(f);
          b64 = base64Encode(await f.readAsBytes());
        }
      }
      // 后台流式接收，但只在完整后一次性显示（避免逐字蹦）
      final buf = StringBuffer();
      await for (final piece in await api.stream(text, imageBase64: b64)) {
        buf.write(piece);
        if (_offline && mounted) setState(() => _offline = false);
      }
      if (!mounted) return;
      final full = buf.toString();
      if (full.trim().isEmpty) {
        reply.text = '（没有收到回复）';
        reply.status = MsgStatus.failed;
      } else {
        // 解析她的小动作（换头像 / 换背景），标记不入正文
        SelfAction? act;
        final cleaned = stripSelfActions(full, (a) => act ??= a);
        var shown = cleaned.isEmpty ? full : cleaned;
        if (act != null && AppPrefs.instance.selfDress) {
          final applied = await _runSelfAction(act!);
          if (applied) {
            shown = '$shown\n\n（她换了个${act!.kind == 'avatar' ? '头像' : '背景'}）';
          }
        }
        setState(() {
          reply.text = shown;
          reply.status = MsgStatus.done;
        });
        Haptics.herMessage();
        _scrollToBottom(jump: true);
      }
    } catch (e) {
      final net = _isNetworkError(e);
      if (net) {
        if (mounted) setState(() => _offline = true);
        if (attempt < 2 && reply.text.isEmpty) {
          await Future.delayed(Duration(milliseconds: 800 + attempt * 700));
          if (!mounted) return;
          reply.text = '';
          reply.status = MsgStatus.pending;
          setState(() {});
          return _request(s, text, imagePath, reply, attempt: attempt + 1);
        }
      }
      reply.text = e is ChatError ? e.message : ChatApi.friendly(e);
      reply.status = MsgStatus.failed;
    } finally {
      await HistoryDb.update(widget.conv, reply);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return GestureDetector(
      onHorizontalDragStart: (_) => _dragDx = 0,
      onHorizontalDragUpdate: (d) => _dragDx += d.delta.dx,
      onHorizontalDragEnd: (d) {
        final fast = (d.primaryVelocity ?? 0) > 350;
        if (_dragDx > 30 || (fast && _dragDx > 12)) {
          Haptics.light();
          Navigator.of(context).maybePop();
        }
        _dragDx = 0;
      },
      child: AnimatedBuilder(
        animation: AppPrefs.instance,
        builder: (context, _) => _buildChat(),
      ),
    );
  }

  /// 会话配色：自定义 > 预设 > 全局
  Palette _resolvePalette(AppPrefs prefs) {
    final custom = _customColors;
    if (custom != null && custom.isNotEmpty) {
      try {
        final m = jsonDecode(custom) as Map<String, dynamic>;
        Color c(String k, Color fallback) {
          final v = m[k];
          if (v is! String) return fallback;
          return Color(int.parse(v.replaceFirst('#', ''), radix: 16) | 0xFF000000);
        }
        return Palette.custom(
          bg: c('bg', prefs.palette.bg),
          accent: c('accent', prefs.palette.accent),
          bubbleMine: c('mine', prefs.palette.bubbleMine),
          bubbleOther: c('other', prefs.palette.bubbleOther),
        );
      } catch (_) {}
    }
    if (_paletteId != null) return paletteById(_paletteId);
    return prefs.palette;
  }

  Widget _buildChat() {
    final prefs = AppPrefs.instance;
    final palette = _resolvePalette(prefs);
    final File? convBg = (_bgPath != null && File(_bgPath!).existsSync())
        ? File(_bgPath!)
        : null;
    final bg = convBg;

    final scaffold = Scaffold(
      key: _scaffoldKey,
      endDrawer: _chatDrawer(palette),
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.name,
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w600)),
                Text('在线',
                    style: TextStyle(fontSize: 11, color: palette.accent)),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
          ),
        ],
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
        child: Column(
          children: [
            if (_offline)
              Container(
                width: double.infinity,
                color: const Color(0xFF8A5A00),
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: const Text(
                  '网络未连接，正在自动重试…',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.white),
                ),
              ),
            if (_loadingMore)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            Expanded(
              child: _msgs.isEmpty
                  ? Center(
                      child: Text('说点什么吧',
                          style: TextStyle(
                              color: palette.fgWith(0.35), fontSize: 14)),
                    )
                  : AnimatedBuilder(
                      animation: _blink,
                      builder: (context, _) => ListView.builder(
                      controller: _scroll,
                      reverse: _msgs.length > 12,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 16),
                      itemCount: _msgs.length,
                      itemBuilder: (c, i) {
                        final rev = _msgs.length > 12;
                        final idx = rev ? _msgs.length - 1 - i : i;
                        final m = _msgs[idx];
                        final older = idx > 0 ? _msgs[idx - 1] : null;
                        final showTime = older == null ||
                            m.time.difference(older.time).inMinutes >= 5;
                        final sameSender = older != null &&
                            older.mine == m.mine &&
                            m.time.difference(older.time).inMinutes < 3;
                        final rowKey = m.id == null
                            ? null
                            : (_msgKeys[m.id!] ??= GlobalKey());
                        final popId = m.id ?? identityHashCode(m);
                        final animate =
                            m.text.trim().isNotEmpty && _poppedIds.add(popId);
                        return _PopBubble(
                          key: ValueKey('pop-$popId'),
                          animate: animate,
                          align: m.mine
                              ? Alignment.bottomRight
                              : Alignment.bottomLeft,
                          child: Column(
                            key: rowKey,
                            children: [
                              _bubble(m, palette,
                                  showAvatar: !sameSender || showTime),
                              if (showTime) _timeLabel(m.time, palette),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
            ),
            _composer(palette),
          ],
        ),
      ),
      floatingActionButton: AnimatedBuilder(
        animation: _scroll,
        builder: (context, _) {
          final hidden = !_scroll.hasClients || _scroll.offset <= 24;
          return AnimatedSlide(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            offset: hidden ? const Offset(0, 0.6) : Offset.zero,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 180),
              opacity: hidden ? 0 : 1,
              child: IgnorePointer(
                ignoring: hidden,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 76),
                  child: FloatingActionButton.small(
                    backgroundColor: palette.surface,
                    foregroundColor: palette.accent,
                    elevation: 4,
                    onPressed: () => _scrollToBottom(),
                    child: const Icon(Icons.arrow_downward),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );

    return Theme(data: buildTheme(palette), child: scaffold);
  }

  Widget _chatDrawer(Palette palette) {
    return Drawer(
      width: MediaQuery.of(context).size.width * 0.55,
      backgroundColor: palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(18),
          bottomLeft: Radius.circular(18),
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
                  Text('会话菜单',
                      style: TextStyle(
                          fontSize: 11, color: palette.fgWith(0.4))),
                ],
              ),
            ),
            const Divider(height: 1),
            const SizedBox(height: 8),

            ListTile(
              leading: Icon(Icons.search, color: palette.accent, size: 22),
              title: const Text('搜索聊天记录'),
              onTap: () {
                Navigator.pop(context);
                _openSearch();
              },
            ),
            ListTile(
              leading: Icon(Icons.settings_outlined,
                  color: palette.accent, size: 22),
              title: const Text('全部设置'),
              onTap: () async {
                Navigator.pop(context);
                final pagePalette = _resolvePalette(AppPrefs.instance);
                await Navigator.of(context).push(
                  themedRoute(
                    pagePalette,
                    SettingsPage(
                      convId: widget.conv,
                      paletteOverride: pagePalette,
                    ),
                  ),
                );
                if (mounted) {
                  await _reloadAppearance();
                  setState(() {});
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openSearch() async {
    final s = _settings;
    if (s == null) return;
    final pagePalette = _resolvePalette(AppPrefs.instance);
    final id = await Navigator.of(context).push<int>(
      themedRoute(pagePalette, SearchPage(conv: widget.conv)),
    );
    if (id == null || !mounted) return;
    await _ensureLoaded(id);
    setState(() => _highlightId = id);
    _jumpToId(id);
  }

  Future<void> _ensureLoaded(int id) async {
    if (_findById(id) != null) return;
    final s = _settings;
    if (s == null) return;
    var rounds = 0;
    while (_findById(id) == null && _msgs.isNotEmpty && rounds < 20) {
      final older = await HistoryDb.before(
          widget.conv, _msgs.first.time.millisecondsSinceEpoch);
      if (older.isEmpty) break;
      if (!mounted) return;
      setState(() => _msgs.insertAll(0, older));
      rounds++;
    }
  }

  Widget _timeLabel(DateTime t, Palette palette) {
    final now = DateTime.now();
    final sameDay =
        t.year == now.year && t.month == now.month && t.day == now.day;
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    final label = sameDay ? '$hh:$mm' : '${t.month}/${t.day} $hh:$mm';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(label,
          style: TextStyle(fontSize: 11, color: palette.fgWith(0.25))),
    );
  }

  /// 选中文字后浮出的工具条：引用 / 复制 / 删除
  Widget _selectionToolbar(BuildContext ctx, EditableTextState state,
      Msg m, Palette palette) {
    final sel = state.textEditingValue.selection;
    final selected = sel.isValid && !sel.isCollapsed
        ? sel.textInside(state.textEditingValue.text)
        : m.text;

    // 每次打开工具条分配一个会话号；同一会话里同一个动作只执行一次
    final sid = identityHashCode(state);
    if (sid != _lastMenuState) {
      _lastMenuState = sid;
      _menuSession++;
      _doneAction = null;
    }
    bool claim(String action) {
      final key = '$_menuSession-$action';
      if (_doneAction == key) return false;
      _doneAction = key;
      return true;
    }

    void clearSelection() {
      // 直接把选区收缩到开头，避免重建组件（重建会触发安卓的编辑菜单）
      try {
        state.userUpdateTextEditingValue(
          state.textEditingValue.copyWith(
            selection: const TextSelection.collapsed(offset: 0),
          ),
          SelectionChangedCause.tap,
        );
      } catch (_) {}
      state.hideToolbar();
      FocusScope.of(context).unfocus();
    }

    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: state.contextMenuAnchors,
      buttonItems: [
        ContextMenuButtonItem(
          label: '引用',
          onPressed: () {
            if (!claim('quote')) return;
            clearSelection();
            _startQuote(m);
          },
        ),
        ContextMenuButtonItem(
          label: '复制',
          onPressed: () async {
            if (!claim('copy')) return;
            final now = DateTime.now();
            if (now.isBefore(_copyLock)) return;
            _copyLock = now.add(const Duration(milliseconds: 300));
            clearSelection();
            await Clipboard.setData(ClipboardData(text: selected));
            Haptics.light();

          },
        ),
        ContextMenuButtonItem(
          label: '复制全部',
          onPressed: () async {
            if (!claim('copyAll')) return;
            final now = DateTime.now();
            if (now.isBefore(_copyLock)) return;
            _copyLock = now.add(const Duration(milliseconds: 300));
            clearSelection();
            await Clipboard.setData(ClipboardData(text: m.text));
            Haptics.light();
          },
        ),
        ContextMenuButtonItem(
          label: '删除',
          onPressed: () {
            if (!claim('delete')) return;
            clearSelection();
            _deleteMsg(m);
          },
        ),
      ],
    );
  }
  Widget _bubble(Msg m, Palette palette, {bool showAvatar = true}) {
    final mine = m.mine;
    final failed = m.status == MsgStatus.failed;
    final opacity = AppPrefs.instance.bubbleOpacity;

    final baseColor = mine ? palette.bubbleMine : palette.bubbleOther;
    final bubbleColor = failed
        ? const Color(0xFF7A3B3B).withValues(alpha: opacity)
        : baseColor.withValues(alpha: opacity);
    final textColor = mine ? Colors.white : palette.fg;
    final align = mine ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final hasImage = m.imagePath != null && File(m.imagePath!).existsSync();
    final hasQuote = m.quoteText != null && m.quoteText!.isNotEmpty;

    final isHi = m.id != null && m.id == _highlightId;

    return Container(
      decoration: isHi
          ? BoxDecoration(
              color: palette.accent
                  .withValues(alpha: 0.10 + 0.18 * _blink.value),
              borderRadius: BorderRadius.circular(14),
            )
          : null,
      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
      child: Row(
        mainAxisAlignment:
            mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!mine)
            showAvatar
                ? _avatar(mine: false, palette: palette)
                : const SizedBox(width: 34),
          if (!mine) const SizedBox(width: 8),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.72,
            ),
            child: Column(
              crossAxisAlignment: align,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: failed ? () => _retry(m) : null,
                  // 有文字时，长按交给文字选择（微信那种）；
                  // 只有图片/空文字才用底部菜单
                  onLongPress: m.text.isEmpty ? () => _showMenu(m) : null,
                  onDoubleTap: () => _copyText(m),
                  child: Container(
                    clipBehavior: Clip.antiAlias,
                    padding:
                        hasImage ? EdgeInsets.zero : const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: bubbleColor,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(12),
                        topRight: const Radius.circular(12),
                        bottomLeft: Radius.circular(mine ? 12 : 4),
                        bottomRight: Radius.circular(mine ? 4 : 12),
                      ),
                      border: null,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (hasQuote)
                          GestureDetector(
                            onTap: () => _jumpTo(_findById(m.quoteMsgId)),
                            child: Container(
                              width: double.infinity,
                              margin: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                              padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                              decoration: BoxDecoration(
                                color: palette.fg.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(8),
                                border: Border(
                                  left: BorderSide(
                                      color: palette.accent, width: 2.5),
                                ),
                              ),
                              child: Text(
                                _quoteTextOf(m),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: textColor.withValues(alpha: 0.75),
                                ),
                              ),
                            ),
                          ),
                        if (hasImage)
                          GestureDetector(
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ImageViewerPage(
                                    file: File(m.imagePath!)),
                              ),
                            ),
                            child: SizedBox(
                              width: 210,
                              height: 280,
                              child: Image.file(
                                File(m.imagePath!),
                                fit: BoxFit.cover,
                                filterQuality: FilterQuality.medium,
                              ),
                            ),
                          ),
                        if (m.status == MsgStatus.pending && m.text.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: _TypingDots(color: textColor),
                          )
                        else if (m.text.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                            child: SelectableText(m.text,
                                key: ValueKey('sel-${m.id}'),
                                contextMenuBuilder: (ctx, state) =>
                                    _selectionToolbar(ctx, state, m, palette),
                                style: TextStyle(
                                    fontSize: 16 *
                                        AppPrefs.instance.fontScale,
                                    height: 1.5,
                                    color: textColor)),
                          ),
                      ],
                    ),
                  ),
                ),
                if (failed)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _retry(m),
                    child: const Padding(
                      padding: EdgeInsets.only(top: 6, left: 4, right: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.refresh,
                              size: 14, color: Colors.redAccent),
                          SizedBox(width: 4),
                          Text('点击重试',
                              style: TextStyle(
                                  fontSize: 11, color: Colors.redAccent)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (mine) const SizedBox(width: 8),
          if (mine)
            showAvatar
                ? _avatar(mine: true, palette: palette)
                : const SizedBox(width: 34),
        ],
      ),
    );
  }

  Widget _avatar({required bool mine, required Palette palette}) {
    final File? f = mine
        ? AppPrefs.instance.myAvatarFile
        : ((_avatarPath != null && File(_avatarPath!).existsSync())
            ? File(_avatarPath!)
            : null);
    if (f != null) {
      return ClipOval(
        child: Image.file(f, width: 34, height: 34, fit: BoxFit.cover),
      );
    }
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: mine ? palette.accent.withValues(alpha: 0.30) : palette.alt,
        shape: BoxShape.circle,
      ),
      child: Icon(
        mine ? Icons.person : Icons.set_meal,
        size: 19,
        color: mine ? Colors.white : palette.fgWith(0.7),
      ),
    );
  }

  Widget _composer(Palette palette) {
    final glass = AppPrefs.instance.glassComposer;
    final inner = Container(
      padding: const EdgeInsets.fromLTRB(6, 8, 10, 10),
      color: glass ? palette.surface.withValues(alpha: 0.32) : palette.surface,
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            if (_quoted != null)
              Container(
                margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
                decoration: BoxDecoration(
                  color: palette.alt,
                  borderRadius: BorderRadius.circular(8),
                  border: Border(
                    left: BorderSide(color: palette.accent, width: 2.5),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '引用：${_quoteTextOf(_quoted!)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12, color: palette.fgWith(0.6)),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      onPressed: () => setState(() => _quoted = null),
                    ),
                  ],
                ),
              ),
            if (_pendingImage != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 0, 8),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(_pendingImage!,
                          width: 64, height: 64, fit: BoxFit.cover),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => setState(() => _pendingImage = null),
                      child: const Text('移除'),
                    ),
                  ],
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  onPressed: _pickImage,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  color: palette.fgWith(0.5),
                ),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: palette.alt,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 5,
                      style: TextStyle(color: palette.fg),
                      textInputAction: TextInputAction.newline,
                      decoration: InputDecoration(
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        hintText: '说点什么…',
                        hintStyle: TextStyle(color: palette.fgWith(0.3)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _sending ? null : _send,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: _sending ? palette.fgWith(0.12) : palette.accent,
                      shape: BoxShape.circle,
                    ),
                    child: _sending
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.arrow_upward, size: 22),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (!glass) return inner;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: AppPrefs.instance.glassSigma,
          sigmaY: AppPrefs.instance.glassSigma,
        ),
        child: inner,
      ),
    );
  }
}

/// 三个跳动的点
class _TypingDots extends StatefulWidget {
  const _TypingDots({required this.color});
  final Color color;

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final t = (_c.value + i * 0.16) % 1.0;
            final scale = 0.7 + 0.5 * (1 - (2 * t - 1).abs());
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              child: Transform.scale(
                scale: scale,
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: widget.color
                        .withValues(alpha: (0.35 + 0.5 * scale).clamp(0.0, 1.0)),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

/// 全屏看图
class ImageViewerPage extends StatelessWidget {
  const ImageViewerPage({super.key, required this.file});
  final File file;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: InteractiveViewer(
              minScale: 0.4,
              maxScale: 6,
              boundaryMargin: const EdgeInsets.all(120),
              child: Center(child: Image.file(file, fit: BoxFit.contain)),
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
    );
  }
}

/// 消息搜索
class SearchPage extends StatefulWidget {
  const SearchPage({super.key, required this.conv});
  final String conv;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _ctl = TextEditingController();
  List<Msg> _results = [];
  bool _searched = false;
  Timer? _debounce;

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _run(value));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctl.dispose();
    super.dispose();
  }

  Future<void> _run(String keyword) async {
    if (keyword.trim().isEmpty) {
      setState(() {
        _results = [];
        _searched = false;
      });
      return;
    }
    final rows = await HistoryDb.search(widget.conv, keyword.trim());
    if (!mounted) return;
    setState(() {
      _results = rows;
      _searched = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPrefs.instance.palette;
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _ctl,
          autofocus: true,
          style: TextStyle(color: palette.fg, fontSize: 16),
          decoration: InputDecoration(
            border: InputBorder.none,
            hintText: '搜索聊天记录',
            hintStyle: TextStyle(color: palette.fgWith(0.35)),
          ),
          onChanged: _onChanged,
          onSubmitted: _run,
        ),
      ),
      body: !_searched
          ? Center(
              child: Text('输入关键词开始搜索',
                  style: TextStyle(color: palette.fgWith(0.35), fontSize: 13)),
            )
          : _results.isEmpty
              ? Center(
                  child: Text('没有找到相关消息',
                      style:
                          TextStyle(color: palette.fgWith(0.35), fontSize: 13)),
                )
              : ListView.builder(
                  itemCount: _results.length,
                  itemBuilder: (c, i) {
                    final m = _results[i];
                    final t = m.time;
                    final stamp =
                        '${t.month}/${t.day} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
                    return ListTile(
                      leading: Icon(
                        m.mine ? Icons.person_outline : Icons.set_meal,
                        color: palette.fgWith(0.5),
                        size: 20,
                      ),
                      title: Text(
                        m.text.replaceAll('\n', ' '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 14, color: palette.fg),
                      ),
                      subtitle: Text(stamp,
                          style: TextStyle(
                              fontSize: 11, color: palette.fgWith(0.3))),
                      onTap: () => Navigator.of(context).pop(m.id),
                    );
                  },
                ),
    );
  }
}
