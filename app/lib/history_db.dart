import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

enum MsgStatus { pending, done, failed }

class Msg {
  Msg({
    this.id,
    required this.text,
    required this.mine,
    required this.time,
    this.status = MsgStatus.done,
    this.retryText,
    this.imagePath,
    this.quoteText,
    this.quoteMsgId,
  });

  int? id;
  String text;
  final bool mine;
  DateTime time;
  MsgStatus status;
  String? retryText;
  String? imagePath;
  String? quoteText;
  int? quoteMsgId;

  Map<String, Object?> toRow(String conv) => {
        'conv': conv,
        'text': text,
        'mine': mine ? 1 : 0,
        'time': time.millisecondsSinceEpoch,
        'status': status.index,
        'retry_text': retryText,
        'image_path': imagePath,
        'quote_text': quoteText,
        'quote_msg_id': quoteMsgId,
      };

  static Msg fromRow(Map<String, Object?> r) => Msg(
        id: r['id'] as int?,
        text: (r['text'] as String?) ?? '',
        mine: (r['mine'] as int? ?? 0) == 1,
        time: DateTime.fromMillisecondsSinceEpoch((r['time'] as int?) ?? 0),
        status: MsgStatus.values[((r['status'] as int?) ?? 1).clamp(0, 2)],
        retryText: r['retry_text'] as String?,
        imagePath: r['image_path'] as String?,
        quoteText: r['quote_text'] as String?,
        quoteMsgId: r['quote_msg_id'] as int?,
      );
}

class Conversation {
  Conversation({
    required this.conv,
    required this.name,
    this.persona,
    this.avatarPath,
    this.bgPath,
    this.paletteId,
    this.customColors,
    this.lastRead = 0,
    this.sortOrder = 0,
    this.apiBase,
    this.apiKey,
    this.model,
    this.systemNote,
    required this.createdAt,
  });

  final String conv;
  String name;
  String? persona;
  String? avatarPath;
  String? bgPath;
  String? paletteId;
  String? customColors;
  int lastRead;
  DateTime createdAt;
  int sortOrder;
  String? apiBase;
  String? apiKey;
  String? model;
  String? systemNote;

  static Conversation fromRow(Map<String, Object?> r) => Conversation(
        conv: (r['conv'] as String?) ?? '',
        name: (r['name'] as String?) ?? '未命名',
        persona: r['persona'] as String?,
        avatarPath: r['avatar_path'] as String?,
        bgPath: r['bg_path'] as String?,
        paletteId: r['palette_id'] as String?,
        customColors: r['custom_colors'] as String?,
        lastRead: (r['last_read'] as int?) ?? 0,
        sortOrder: (r['sort_order'] as int?) ?? 0,
        apiBase: r['api_base'] as String?,
        apiKey: r['api_key'] as String?,
        model: r['model'] as String?,
        systemNote: r['system_note'] as String?,
        createdAt: DateTime.fromMillisecondsSinceEpoch((r['created_at'] as int?) ?? 0),
      );
}

class AlbumItem {
  AlbumItem({
    this.id,
    required this.path,
    required this.createdAt,
    this.source,
    this.msgId,
  });

  int? id;
  final String path;
  final DateTime createdAt;
  final String? source;
  final int? msgId;

  static AlbumItem fromRow(Map<String, Object?> r) => AlbumItem(
        id: r['id'] as int?,
        path: (r['path'] as String?) ?? '',
        createdAt:
            DateTime.fromMillisecondsSinceEpoch((r['created_at'] as int?) ?? 0),
        source: r['source'] as String?,
        msgId: r['msg_id'] as int?,
      );
}

class HistoryDb {
  static Database? _db;

  static Future<Database> _open() async {
    if (_db != null) return _db!;
    final dir = await getDatabasesPath();
    final path = p.join(dir, 'dafeiyu.db');
    _db = await openDatabase(
      path,
      version: 9,
      onCreate: (db, v) async {
        await db.execute('''
          CREATE TABLE messages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            conv TEXT NOT NULL,
            text TEXT NOT NULL,
            mine INTEGER NOT NULL,
            time INTEGER NOT NULL,
            status INTEGER NOT NULL,
            retry_text TEXT,
            image_path TEXT,
            quote_text TEXT,
            quote_msg_id INTEGER
          )
        ''');
        await db.execute('CREATE INDEX idx_conv_time ON messages(conv, time)');
        await db.execute('''
          CREATE TABLE conversations (
            conv TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            persona TEXT,
            avatar_path TEXT,
            last_read INTEGER NOT NULL DEFAULT 0,
            created_at INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE album (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            path TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            source TEXT,
            msg_id INTEGER
          )
        ''');
      },
      onUpgrade: (db, oldV, newV) async {
        if (oldV < 2) {
          await db.execute('ALTER TABLE messages ADD COLUMN quote_text TEXT');
          await db.execute(
              'ALTER TABLE messages ADD COLUMN quote_msg_id INTEGER');
        }
        if (oldV < 9) {
          try {
            await db.execute('ALTER TABLE conversations ADD COLUMN system_note TEXT');
          } catch (_) {}
        }
        if (oldV < 8) {
          for (final col in ['api_base', 'api_key', 'model']) {
            try {
              await db.execute('ALTER TABLE conversations ADD COLUMN $col TEXT');
            } catch (_) {}
          }
        }
        if (oldV < 7) {
          try { await db.execute('ALTER TABLE conversations ADD COLUMN sort_order INTEGER NOT NULL DEFAULT 0'); } catch (_) {}
          try {
            await db.execute('UPDATE conversations SET sort_order = rowid WHERE sort_order = 0');
          } catch (_) {}
        }
        if (oldV < 6) {
          try { await db.execute('ALTER TABLE conversations ADD COLUMN custom_colors TEXT'); } catch (_) {}
        }
        if (oldV < 5) {
          try { await db.execute('ALTER TABLE conversations ADD COLUMN bg_path TEXT'); } catch (_) {}
          try { await db.execute('ALTER TABLE conversations ADD COLUMN palette_id TEXT'); } catch (_) {}
        }
        if (oldV < 4) {
          await db.execute('''
            CREATE TABLE conversations (
              conv TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              persona TEXT,
              avatar_path TEXT,
              bg_path TEXT,
              palette_id TEXT,
              custom_colors TEXT,
              last_read INTEGER NOT NULL DEFAULT 0,
              created_at INTEGER NOT NULL,
              sort_order INTEGER NOT NULL DEFAULT 0,
              api_base TEXT,
              api_key TEXT,
              model TEXT,
              system_note TEXT
            )
          ''');
        }
        if (oldV < 3) {
          await db.execute('''
            CREATE TABLE album (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              path TEXT NOT NULL,
              created_at INTEGER NOT NULL,
              source TEXT,
              msg_id INTEGER
            )
          ''');
        }
      },
    );
    return _db!;
  }

  static Future<int> insert(String conv, Msg m) async {
    final db = await _open();
    final id = await db.insert('messages', m.toRow(conv));
    m.id = id;
    return id;
  }

  static Future<void> update(String conv, Msg m) async {
    if (m.id == null) return;
    final db = await _open();
    await db.update('messages', m.toRow(conv), where: 'id = ?', whereArgs: [m.id]);
  }

  static Future<List<Msg>> recent(String conv, {int limit = 200}) async {
    final db = await _open();
    final rows = await db.query(
      'messages',
      where: 'conv = ?',
      whereArgs: [conv],
      orderBy: 'time DESC, id DESC',
      limit: limit,
    );
    return rows.map(Msg.fromRow).toList().reversed.toList();
  }

  static Future<List<Msg>> before(String conv, int timeMs,
      {int limit = 100}) async {
    final db = await _open();
    final rows = await db.query(
      'messages',
      where: 'conv = ? AND time < ?',
      whereArgs: [conv, timeMs],
      orderBy: 'time DESC, id DESC',
      limit: limit,
    );
    return rows.map(Msg.fromRow).toList().reversed.toList();
  }

  static Future<int> count(String conv) async {
    final db = await _open();
    final r = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM messages WHERE conv = ?', [conv]);
    return (r.first['c'] as int?) ?? 0;
  }

  static Future<List<Msg>> search(String conv, String keyword,
      {int limit = 120}) async {
    final db = await _open();
    final rows = await db.query(
      'messages',
      where: 'conv = ? AND text LIKE ?',
      whereArgs: [conv, '%$keyword%'],
      orderBy: 'time DESC',
      limit: limit,
    );
    return rows.map(Msg.fromRow).toList();
  }

  static Future<int> unread(String conv, int sinceMs) async {
    final db = await _open();
    final r = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM messages WHERE conv = ? AND mine = 0 AND time > ?',
      [conv, sinceMs],
    );
    return (r.first['c'] as int?) ?? 0;
  }

  static Future<void> deleteOne(int id) async {
    final db = await _open();
    await db.delete('messages', where: 'id = ?', whereArgs: [id]);
  }

  // ── 会话 ──
  static Future<List<Conversation>> convList() async {
    final db = await _open();
    final rows = await db.query('conversations',
        orderBy: 'sort_order ASC, created_at ASC');
    return rows.map(Conversation.fromRow).toList();
  }

  static Future<Conversation?> convGet(String conv) async {
    final db = await _open();
    final rows =
        await db.query('conversations', where: 'conv = ?', whereArgs: [conv]);
    if (rows.isEmpty) return null;
    return Conversation.fromRow(rows.first);
  }

  static Future<void> convUpsert(Conversation c) async {
    final db = await _open();
    await db.insert(
      'conversations',
      {
        'conv': c.conv,
        'name': c.name,
        'persona': c.persona,
        'avatar_path': c.avatarPath,
        'bg_path': c.bgPath,
        'palette_id': c.paletteId,
        'custom_colors': c.customColors,
        'last_read': c.lastRead,
        'created_at': c.createdAt.millisecondsSinceEpoch,
        'sort_order': c.sortOrder,
        'api_base': c.apiBase,
        'api_key': c.apiKey,
        'model': c.model,
        'system_note': c.systemNote,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 按传入顺序重写 sort_order
  static Future<void> convReorder(List<String> orderedConvs) async {
    final db = await _open();
    final batch = db.batch();
    for (var i = 0; i < orderedConvs.length; i++) {
      batch.update('conversations', {'sort_order': i + 1},
          where: 'conv = ?', whereArgs: [orderedConvs[i]]);
    }
    await batch.commit(noResult: true);
  }

  /// 新会话排到最后
  static Future<int> convNextSort() async {
    final db = await _open();
    final rows = await db.rawQuery(
        'SELECT MAX(sort_order) AS m FROM conversations');
    final m = (rows.first['m'] as int?) ?? 0;
    return m + 1;
  }

  static Future<void> convMarkRead(String conv, int ms) async {
    final db = await _open();
    await db.update('conversations', {'last_read': ms},
        where: 'conv = ?', whereArgs: [conv]);
  }

  static Future<void> convDelete(String conv) async {
    final db = await _open();
    await db.delete('conversations', where: 'conv = ?', whereArgs: [conv]);
  }

  static Future<int> convUnread(String conv, int sinceMs) => unread(conv, sinceMs);

  // ── 相册 ──
  static Future<int> albumAdd(AlbumItem item) async {
    final db = await _open();
    return db.insert('album', {
      'path': item.path,
      'created_at': item.createdAt.millisecondsSinceEpoch,
      'source': item.source,
      'msg_id': item.msgId,
    });
  }

  static Future<List<AlbumItem>> albumList() async {
    final db = await _open();
    final rows = await db.query('album', orderBy: 'created_at DESC');
    return rows.map(AlbumItem.fromRow).toList();
  }

  static Future<void> albumRemove(int id) async {
    final db = await _open();
    await db.delete('album', where: 'id = ?', whereArgs: [id]);
  }

  static Future<bool> albumHas(String path) async {
    final db = await _open();
    final rows =
        await db.query('album', where: 'path = ?', whereArgs: [path], limit: 1);
    return rows.isNotEmpty;
  }

  static Future<void> clear(String conv) async {
    final db = await _open();
    await db.delete('messages', where: 'conv = ?', whereArgs: [conv]);
  }

  static Future<void> deleteConversationImages(int unused) async {}
}

Future<String> copyToAppDir(File src, {String prefix = 'img'}) async {
  final dir = Directory(p.join((await getDatabasesPath()), 'images'));
  if (!await dir.exists()) await dir.create(recursive: true);
  final rnd = DateTime.now().microsecondsSinceEpoch
      .toRadixString(36)
      .substring(4);
  final name = '${prefix}_${DateTime.now().millisecondsSinceEpoch}_$rnd'
      '${p.extension(src.path).isEmpty ? '.jpg' : p.extension(src.path)}';
  final dst = p.join(dir.path, name);
  await src.copy(dst);
  return dst;
}
