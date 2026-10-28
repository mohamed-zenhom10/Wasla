import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

const maxImageDimension = 1280;

Uint8List compressImageForUpload(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw const FormatException('تعذّر قراءة الصورة لتجهيزها للإرسال.');
  }

  final oriented = img.bakeOrientation(decoded);
  final longestSide = oriented.width > oriented.height
      ? oriented.width
      : oriented.height;
  final resized = longestSide > maxImageDimension
      ? img.copyResize(
          oriented,
          width: maxImageDimension,
          height: maxImageDimension,
          maintainAspect: true,
          interpolation: img.Interpolation.average,
        )
      : oriented;

  return Uint8List.fromList(
    img.encodeJpg(resized, quality: 78, chroma: img.JpegChroma.yuv420),
  );
}

Future<Uint8List> prepareImageForUpload(Uint8List bytes) {
  return compute(
    compressImageForUpload,
    bytes,
    debugLabel: 'compressCargoImage',
  );
}
