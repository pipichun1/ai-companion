import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 把图片压到适合上传的大小：最长边 <= 1280，JPEG 质量 72。
/// 已经是小图就原样返回。
Future<File> compressForUpload(File src, {int maxSide = 1280, int quality = 72}) async {
  final bytes = await src.readAsBytes();
  if (bytes.length <= 700 * 1024) return src;

  img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    return src;
  }
  if (decoded == null) return src;

  var image = decoded;
  final longest = image.width > image.height ? image.width : image.height;
  if (longest > maxSide) {
    final scale = maxSide / longest;
    image = img.copyResize(
      image,
      width: (image.width * scale).round(),
      height: (image.height * scale).round(),
      interpolation: img.Interpolation.average,
    );
  }

  final encoded = img.encodeJpg(image, quality: quality);
  final dir = await getTemporaryDirectory();
  final out = File(p.join(dir.path, 'up_${DateTime.now().millisecondsSinceEpoch}.jpg'));
  await out.writeAsBytes(encoded, flush: true);
  return out;
}
