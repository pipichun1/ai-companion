import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3, Matrix4;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 简易裁剪页：拖动/双指缩放，框内即为结果。
class CropPage extends StatefulWidget {
  const CropPage({
    super.key,
    required this.file,
    this.aspectRatio = 1.0,
    this.outputSize = 512,
    this.title = '调整图片',
  });

  final File file;
  final double aspectRatio;
  final int outputSize;
  final String title;

  @override
  State<CropPage> createState() => _CropPageState();
}

class _CropPageState extends State<CropPage> {
  final _boundaryKey = GlobalKey();
  final _transformController = TransformationController();
  bool _saving = false;

  /// 按当前缩放/位移算出"框内看到的原始图像区域"，直接重绘输出。
  /// 不用截图，避免把整张图或错位的画面当成结果。
  /// 用变换矩阵的逆，把裁剪框四角映射回原图坐标，直接重绘。
  Future<void> _confirm() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final boundary = _boundaryKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      final box = boundary.size;

      final bytes = await widget.file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final src = frame.image;
      final iw = src.width.toDouble();
      final ih = src.height.toDouble();

      // 子控件尺寸 = 裁剪框尺寸（Image 用 cover 在内部裁切）
      final coverScale = math.max(box.width / iw, box.height / ih);
      final drawnW = iw * coverScale;
      final drawnH = ih * coverScale;
      // 图片在子控件里的居中偏移
      final offX = (box.width - drawnW) / 2;
      final offY = (box.height - drawnH) / 2;

      // 屏幕坐标 -> 子控件坐标（逆矩阵）
      final inv = Matrix4.inverted(_transformController.value);
      Offset toChild(Offset screen) {
        final v = inv.transform3(Vector3(screen.dx, screen.dy, 0));
        return Offset(v.x, v.y);
      }

      final tl = toChild(Offset.zero);
      final br = toChild(Offset(box.width, box.height));

      // 子控件坐标 -> 原图坐标
      final rect = Rect.fromLTRB(
        ((tl.dx - offX) / coverScale).clamp(0.0, iw),
        ((tl.dy - offY) / coverScale).clamp(0.0, ih),
        ((br.dx - offX) / coverScale).clamp(0.0, iw),
        ((br.dy - offY) / coverScale).clamp(0.0, ih),
      );

      final safe = Rect.fromLTRB(
        math.min(rect.left, iw - 1),
        math.min(rect.top, ih - 1),
        math.max(rect.right, rect.left + 1),
        math.max(rect.bottom, rect.top + 1),
      );

      final outW = widget.outputSize;
      final outH = (widget.outputSize / widget.aspectRatio).round();

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImageRect(
        src,
        safe,
        Rect.fromLTWH(0, 0, outW.toDouble(), outH.toDouble()),
        Paint()..filterQuality = FilterQuality.high,
      );
      final picture = recorder.endRecording();
      final outImage = await picture.toImage(outW, outH);
      final byteData =
          await outImage.toByteData(format: ui.ImageByteFormat.png);

      final dir = await getApplicationDocumentsDirectory();
      final out = File(p.join(dir.path,
          'crop_${DateTime.now().millisecondsSinceEpoch}.png'));
      await out.writeAsBytes(byteData!.buffer.asUint8List(), flush: true);

      if (!mounted) return;
      Navigator.of(context).pop<String>(out.path);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('裁剪失败：$e')));
    }
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(widget.title),
        actions: [
          TextButton(
            onPressed: _saving ? null : _confirm,
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('完成'),
          ),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 24),
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: widget.aspectRatio,
                child: ClipRect(
                  child: RepaintBoundary(
                    key: _boundaryKey,
                    child: InteractiveViewer(
                      transformationController: _transformController,
                      minScale: 1,
                      maxScale: 6,
                      boundaryMargin: EdgeInsets.zero,
                      child: Image.file(
                        widget.file,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Text(
              '拖动或双指缩放，框内即为最终效果',
              style: TextStyle(
                  fontSize: 12, color: Colors.white.withValues(alpha: 0.5)),
            ),
          ),
        ],
      ),
    );
  }
}
