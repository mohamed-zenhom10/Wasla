import 'dart:convert';

import 'package:http/http.dart' as http;

class NationalIdOcrException implements Exception {
  const NationalIdOcrException(this.message);

  final String message;

  @override
  String toString() => message;
}

class NationalIdOcrService {
  NationalIdOcrService({http.Client? client, String? apiKey})
    : _client = client ?? http.Client(),
      _apiKey = apiKey ?? _configuredApiKey;

  static const _configuredApiKey = String.fromEnvironment(
    'NATIONAL_ID_OCR_API_KEY',
  );
  static const _endpoint = String.fromEnvironment(
    'NATIONAL_ID_OCR_API_URL',
    defaultValue: 'https://api.ocr.space/parse/image',
  );

  final http.Client _client;
  final String _apiKey;

  Future<String> readNationalId({
    required List<int> imageBytes,
    required String filename,
  }) async {
    if (_apiKey.isEmpty) {
      throw const NationalIdOcrException(
        'خدمة قراءة الهوية غير مهيأة. أضف مفتاح OCR قبل تشغيل التطبيق.',
      );
    }

    final request = http.MultipartRequest('POST', Uri.parse(_endpoint))
      ..headers['apikey'] = _apiKey
      ..fields['language'] = 'auto'
      ..fields['OCREngine'] = '2'
      ..fields['isOverlayRequired'] = 'false'
      ..files.add(
        http.MultipartFile.fromBytes('file', imageBytes, filename: filename),
      );

    final response = await _client
        .send(request)
        .timeout(const Duration(seconds: 90))
        .then(http.Response.fromStream)
        .timeout(const Duration(seconds: 90));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw NationalIdOcrException(
        'تعذر قراءة الصورة (HTTP ${response.statusCode}). حاول مرة أخرى.',
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw const NationalIdOcrException(
        'استجابة خدمة قراءة الهوية غير صالحة.',
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const NationalIdOcrException(
        'استجابة خدمة قراءة الهوية غير صالحة.',
      );
    }
    if (decoded['IsErroredOnProcessing'] == true) {
      final details = decoded['ErrorMessage'];
      throw NationalIdOcrException(
        details is List && details.isNotEmpty
            ? 'تعذرت قراءة الصورة: ${details.join(' ')}'
            : 'تعذرت قراءة الصورة. اختر صورة أوضح للوجه الأمامي.',
      );
    }

    final results = decoded['ParsedResults'];
    final text = results is List
        ? results
              .whereType<Map>()
              .map((page) => page['ParsedText'])
              .whereType<String>()
              .join('\n')
        : '';
    return extractNationalId(text);
  }

  static String normalizeDigits(String value) {
    const arabicIndicDigits = '٠١٢٣٤٥٦٧٨٩';
    const easternArabicDigits = '۰۱۲۳۴۵۶۷۸۹';

    return value.split('').map((character) {
      final arabicIndex = arabicIndicDigits.indexOf(character);
      if (arabicIndex >= 0) return '$arabicIndex';
      final easternIndex = easternArabicDigits.indexOf(character);
      if (easternIndex >= 0) return '$easternIndex';
      return character;
    }).join();
  }

  static bool matches(String enteredId, String recognizedId) =>
      normalizeDigits(enteredId).trim() == recognizedId;

  static String extractNationalId(String text) {
    final numberPattern = RegExp(
      r'(?<![0-9٠-٩۰-۹])[0-9٠-٩۰-۹](?:[\s-]*[0-9٠-٩۰-۹]){13}(?![0-9٠-٩۰-۹])',
    );
    final candidates = numberPattern
        .allMatches(text)
        .map(
          (match) =>
              normalizeDigits(match.group(0)!.replaceAll(RegExp(r'[\s-]'), '')),
        )
        .toSet();

    if (candidates.isEmpty) {
      throw const NationalIdOcrException(
        'لم يتم العثور على رقم قومي من 14 رقمًا. اختر صورة أوضح للوجه الأمامي.',
      );
    }
    if (candidates.length > 1) {
      throw const NationalIdOcrException(
        'تم العثور على أكثر من رقم محتمل. اختر صورة أوضح تحتوي على رقم قومي واحد.',
      );
    }
    return candidates.single;
  }

  void close() => _client.close();
}
