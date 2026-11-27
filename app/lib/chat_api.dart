import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class ChatApi {
  ChatApi({
    required this.base,
    required this.token,
    required this.conv,
    this.model,
    this.systemNote,
    this.direct = false,
  });

  final String base;
  final String token;
  final String conv;

  /// 直连模式：base 是 OpenAI 兼容的根地址（如 https://api.openai.com/v1），
  /// 请求走 /chat/completions，不再经过自家桥。
  final String? model;

  /// 直连模式下的自定义人设，会作为 system 消息发过去
  final String? systemNote;
  final bool direct;

  String get _url {
    var b = base.trim();
    while (b.endsWith('/')) {
      b = b.substring(0, b.length - 1);
    }
    if (direct) return '$b/chat/completions';
    return '$b/api/v1/plugins/extensions/v1/chat/completions';
  }

  String get _model => (model == null || model!.isEmpty) ? 'se-se-yu' : model!;

  Future<Stream<String>> stream(String text, {String? imageBase64}) async {
    final client = http.Client();
    final req = http.Request('POST', Uri.parse(_url));
    req.headers['Content-Type'] = 'application/json';
    req.headers['Authorization'] = 'Bearer $token';

    final content = <Map<String, dynamic>>[
      if (text.isNotEmpty) {'type': 'text', 'text': text},
      if (imageBase64 != null)
        {
          'type': 'image_url',
          'image_url': {'url': 'data:image/jpeg;base64,$imageBase64'},
        },
    ];

    req.body = jsonEncode({
      'model': _model,
      'stream': true,
      'user': conv,
      'messages': [
        if (direct && systemNote != null && systemNote!.trim().isNotEmpty)
          {'role': 'system', 'content': systemNote!.trim()},
        {
          'role': 'user',
          'content': content.length == 1 && content.first['type'] == 'text'
              ? text
              : content,
        }
      ],
    });

    final resp = await client.send(req).timeout(const Duration(seconds: 25));

    if (resp.statusCode != 200) {
      final body = await resp.stream.bytesToString();
      client.close();
      final cut = body.length > 200 ? body.substring(0, 200) : body;
      throw ChatError('连接失败（${resp.statusCode}）\n$cut');
    }

    final controller = StreamController<String>();
    var buffer = '';
    var closed = false;
    Timer? idle;
    void armIdle() {
      idle?.cancel();
      idle = Timer(const Duration(seconds: 25), () {
        if (closed) return;
        closed = true;
        client.close();
        controller.addError('连接断了（25 秒没有响应）');
        controller.close();
      });
    }
    armIdle();
    resp.stream.transform(utf8.decoder).listen(
      (chunk) {
        armIdle();
        buffer += chunk;
        while (true) {
          final idx = buffer.indexOf('\n');
          if (idx < 0) break;
          final line = buffer.substring(0, idx).trim();
          buffer = buffer.substring(idx + 1);
          if (line.isEmpty || !line.startsWith('data:')) continue;
          final payload = line.substring(5).trim();
          if (payload == '[DONE]') continue;
          try {
            final obj = jsonDecode(payload) as Map<String, dynamic>;
            final choices = obj['choices'] as List?;
            if (choices == null || choices.isEmpty) continue;
            final delta = choices[0]['delta'] as Map?;
            final piece = delta?['content'];
            if (piece is String && piece.isNotEmpty) controller.add(piece);
          } catch (_) {}
        }
      },
      onDone: () {
        idle?.cancel();
        if (closed) return;
        closed = true;
        client.close();
        controller.close();
      },
      onError: (Object e) {
        idle?.cancel();
        if (closed) return;
        closed = true;
        client.close();
        controller.addError(_friendly(e));
        controller.close();
      },
      cancelOnError: true,
    );
    return controller.stream;
  }

  static String friendly(Object e) {
    final s = e.toString();
    if (s.contains('413')) {
      return '图片太大了，服务器拒收——换一张小一点的';
    }
    if (s.contains('Failed host lookup')) {
      return '域名解析失败——检查网络，或确认服务器地址填写正确';
    }
    if (s.contains('TimeoutException')) return '超时了，网络可能不太稳';
    if (s.contains('Connection abort') || s.contains('connection abort')) {
      return '上传中断了，大概是网络太慢或者图太大\n试试换一张小图，或者切到 Wi-Fi';
    }
    if (s.contains('Connection refused') || s.contains('Connection reset')) {
      return '连不上服务器（连接被拒或被重置）';
    }
    return '出错了：$s';
  }

  /// 预热连接：只为了让后续请求复用 TLS 连接
  /// 一次性取完整回复（不流式），让整段文字瞬间出现
  Future<String> complete(String text,
      {String? imageBase64, List<String>? images}) async {
    final list = <String>[
      if (imageBase64 != null) imageBase64,
      ...?images,
    ];
    final messages = <Map<String, dynamic>>[
      if (direct && systemNote != null && systemNote!.trim().isNotEmpty)
        {'role': 'system', 'content': systemNote!.trim()},
      {
        'role': 'user',
        'content': list.isEmpty
            ? text
            : [
                {'type': 'text', 'text': text},
                for (final b in list)
                  {
                    'type': 'image_url',
                    'image_url': {'url': 'data:image/jpeg;base64,$b'},
                  },
              ],
      }
    ];
    final resp = await http
        .post(
          Uri.parse(_url),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'model': _model,
            'stream': false,
            'user': conv,
            'messages': messages,
          }),
        )
        .timeout(const Duration(seconds: 180));
    if (resp.statusCode != 200) {
      throw ChatError('服务返回 ${resp.statusCode}');
    }
    final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    final choices = (data['choices'] as List?) ?? const [];
    if (choices.isEmpty) throw ChatError('她好像没说话');
    final msg = (choices.first as Map)['message'] as Map? ?? const {};
    final content = (msg['content'] ?? '').toString();
    if (content.trim().isEmpty) throw ChatError('她好像没说话');
    return content;
  }

  static bool _isNetwork(Object e) {
    final t = e.toString();
    return t.contains('SocketException') ||
        t.contains('HandshakeException') ||
        t.contains('TimeoutException') ||
        t.contains('ClientException') ||
        t.contains('Connection');
  }

  Future<T> _withRetry<T>(Future<T> Function() run, {int times = 3}) async {
    Object? last;
    for (var i = 0; i < times; i++) {
      try {
        return await run();
      } catch (e) {
        last = e;
        if (!_isNetwork(e) || i == times - 1) rethrow;
        await Future.delayed(Duration(milliseconds: 700 * (i + 1)));
      }
    }
    throw last!;
  }

  Future<void> warmup() async {
    try {
      await http
          .get(Uri.parse('$base/api/stat/versions'))
          .timeout(const Duration(seconds: 6));
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> listPersonas() => _withRetry(() async {
    final resp = await http.get(
      Uri.parse('$base/api/v1/plugins/extensions/v1/personas'),
      headers: {'Authorization': 'Bearer $token'},
    ).timeout(const Duration(seconds: 20));
    if (resp.statusCode != 200) {
      throw ChatError('获取人格失败（${resp.statusCode}）');
    }
    final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    final list = (data['data'] as List?) ?? [];
    return list.map((e) => e as Map<String, dynamic>).toList();
  });

  Future<void> deleteSession(String convId) => _withRetry(() async {
        final resp = await http
            .post(
              Uri.parse('$base/api/v1/plugins/extensions/v1/sessions/delete'),
              headers: {
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/json',
              },
              body: jsonEncode({'conv_id': convId}),
            )
            .timeout(const Duration(seconds: 30));
        if (resp.statusCode != 200) {
          throw ChatError('删除云端记忆失败（${resp.statusCode}）');
        }
      });

  Future<Map<String, dynamic>> createSession(
          String name, String personaFile) =>
      _withRetry(() async {
        final resp = await http
            .post(
              Uri.parse('$base/api/v1/plugins/extensions/v1/sessions'),
              headers: {
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/json',
              },
              body: jsonEncode({'name': name, 'persona_file': personaFile}),
            )
            .timeout(const Duration(seconds: 30));
        if (resp.statusCode != 200) {
          throw ChatError('新建会话失败（${resp.statusCode}）');
        }
        return jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      });
}

class ChatError implements Exception {
  ChatError(this.message);
  final String message;
  @override
  String toString() => message;
}

String _friendly(Object e) => ChatApi.friendly(e);
