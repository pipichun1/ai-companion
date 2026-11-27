import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'history_db.dart';
import 'img_util.dart';

/// 「可用动作」说明：告诉模型它有哪些小动作可以触发。
///
/// 这段文案同时用于：
///   - 直连模式（App 拼进 system 提示词）
///   - 桥模式（插件注入，文案在仓库里保持一致）
///
/// 想加新动作，只改这里 + 解析逻辑，别散落在各处。
const String kAbilitiesNote = '''
你有两个小动作可以触发。注意：你不需要真的去翻相册、也不需要会画图——
只要写出标记，客户端会自动替你完成。

[[换头像]]      换一张头像
[[换背景]]      换一张聊天背景
[[换头像:3]]    指定第 3 张

用法：
- 当对方说"换个头像吧""你自己挑一张"这类话时，
  直接输出 [[换头像]] 就行，不要解释"我做不到""我看不到相册""生图没接上"。
- 平时不要主动用，也不要提这件事；一天最多一次。
- 用了不要解释这个标记，像随口一做。
''';

/// 解析出来的动作
class SelfAction {
  SelfAction(this.kind, {this.index});

  /// avatar / background
  final String kind;

  /// 指定第几张（1 开始），null 表示随机/最近
  final int? index;
}

final RegExp _marker = RegExp(r'\[\[(换头像|换背景)(?::(\d+))?\]\]');

/// 从回复里摘出动作标记，返回清理后的正文 + 第一个动作。
String stripSelfActions(String text, void Function(SelfAction) onAction) {
  var out = text;
  for (final m in _marker.allMatches(text).toList().reversed) {
    final kind = m.group(1) == '换头像' ? 'avatar' : 'background';
    final idx = m.group(2) == null ? null : int.tryParse(m.group(2)!);
    onAction(SelfAction(kind, index: idx));
    out = out.replaceRange(m.start, m.end, '');
  }
  return out.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
}

/// 今天是否已经换过（同一个会话，一天只允许一次）
Future<bool> dressedToday(String conv) async {
  final p = await SharedPreferences.getInstance();
  final today = DateTime.now().toIso8601String().substring(0, 10);
  return p.getString('dressed_${conv}_$today') == '1';
}

Future<void> markDressed(String conv) async {
  final p = await SharedPreferences.getInstance();
  final today = DateTime.now().toIso8601String().substring(0, 10);
  await p.setString('dressed_${conv}_$today', '1');
}

/// 从相册挑一张图并应用到会话外观。
///
/// 返回新的文件路径；没有可用图片时返回 null。
Future<String?> applySelfAction({
  required String conv,
  required SelfAction action,
}) async {
  final items = await HistoryDb.albumList();
  if (items.isEmpty) return null;

  // 相册按时间倒序（最近的在前），优先用最近的图
  final usable = items.where((e) {
    final p = e.path;
    return p != null && File(p).existsSync();
  }).toList();
  if (usable.isEmpty) return null;

  AlbumItem pick;
  final idx = action.index;
  if (idx != null && idx >= 1 && idx <= usable.length) {
    pick = usable[idx - 1];
  } else {
    // 大多数时候用最近的一张，偶尔退一张，避免每次都一样
    final roll = DateTime.now().millisecond % 4;
    final pos = roll == 0 && usable.length > 1 ? 1 : 0;
    pick = usable[pos];
  }

  final old = await HistoryDb.convGet(conv);
  if (old == null) return null;

  final updated = Conversation(
    conv: old.conv,
    name: old.name,
    persona: old.persona,
    avatarPath: action.kind == 'avatar' ? pick.path : old.avatarPath,
    bgPath: action.kind == 'background' ? pick.path : old.bgPath,
    paletteId: old.paletteId,
    customColors: old.customColors,
    createdAt: old.createdAt,
    sortOrder: old.sortOrder,
    lastRead: old.lastRead,
    apiBase: old.apiBase,
    apiKey: old.apiKey,
    model: old.model,
    systemNote: old.systemNote,
  );;
  await HistoryDb.convUpsert(updated);
  return pick.path;
}

/// 取相册里最近若干张图，压缩后转成 base64，供"让她真的看一眼"用。
Future<List<String>> albumCandidatesBase64({int max = 6}) async {
  final items = await HistoryDb.albumList();
  final out = <String>[];
  for (final it in items) {
    if (out.length >= max) break;
    final p = it.path;
    if (p == null) continue;
    final f = File(p);
    if (!await f.exists()) continue;
    try {
      final c = await compressForUpload(f);
      out.add(base64Encode(await c.readAsBytes()));
    } catch (_) {
      // 单张失败不影响其它
    }
  }
  return out;
}