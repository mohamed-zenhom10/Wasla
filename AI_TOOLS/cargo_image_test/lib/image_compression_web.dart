import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'image_compression_stub.dart' show maxImageDimension;

Future<Uint8List> prepareImageForUpload(Uint8List bytes) async {
  final source = web.Blob([bytes.toJS].toJS);
  final objectUrl = web.URL.createObjectURL(source);
  final image = web.document.createElement('img') as web.HTMLImageElement;

  try {
    final loaded = Completer<void>();
    image.addEventListener(
      'load',
      ((web.Event _) {
        loaded.complete();
      }).toJS,
    );
    image.addEventListener(
      'error',
      ((web.Event _) {
        loaded.completeError(
          const FormatException('تعذّر قراءة الصورة لتجهيزها للإرسال.'),
        );
      }).toJS,
    );
    image.src = objectUrl;
    await loaded.future;

    final longestSide = image.naturalWidth > image.naturalHeight
        ? image.naturalWidth
        : image.naturalHeight;
    final scale = longestSide > maxImageDimension
        ? maxImageDimension / longestSide
        : 1.0;
    final width = (image.naturalWidth * scale).round();
    final height = (image.naturalHeight * scale).round();
    final canvas = web.document.createElement('canvas') as web.HTMLCanvasElement
      ..width = width
      ..height = height;
    canvas.context2D.drawImage(image, 0, 0, width, height);

    final compressed = Completer<web.Blob>();
    canvas.toBlob(
      ((web.Blob? blob) {
        if (blob == null) {
          compressed.completeError(
            const FormatException('تعذّر تجهيز الصورة للإرسال.'),
          );
        } else {
          compressed.complete(blob);
        }
      }).toJS,
      'image/jpeg',
      0.78.toJS,
    );
    final blob = await compressed.future;
    final buffer = await blob.arrayBuffer().toDart;
    return JSUint8Array(buffer).toDart;
  } finally {
    web.URL.revokeObjectURL(objectUrl);
  }
}
