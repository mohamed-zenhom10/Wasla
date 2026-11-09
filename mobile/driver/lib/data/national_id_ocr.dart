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
  }) async => extractNationalId(
    await readDocumentText(imageBytes: imageBytes, filename: filename),
  );

  Future<String> readDocumentText({
    required List<int> imageBytes,
    required String filename,
  }) async {
    if (_apiKey.isEmpty) {
      throw const NationalIdOcrException(
        'خدمة OCR غير مهيأة. أضف مفتاح OCR قبل تشغيل التطبيق.',
      );
    }

    final request = http.MultipartRequest('POST', Uri.parse(_endpoint))
      ..headers['apikey'] = _apiKey
      ..fields['language'] = 'auto'
      ..fields['OCREngine'] = '2'
      ..fields['scale'] = 'true'
      ..fields['detectOrientation'] = 'true'
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
            : 'تعذرت قراءة الصورة. اختر صورة أوضح للمستند.',
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
    return text;
  }

  static const _governorates = <String, String>{
    '01': 'القاهرة',
    '02': 'الإسكندرية',
    '03': 'بورسعيد',
    '04': 'السويس',
    '11': 'دمياط',
    '12': 'الدقهلية',
    '13': 'الشرقية',
    '14': 'القليوبية',
    '15': 'كفر الشيخ',
    '16': 'الغربية',
    '17': 'المنوفية',
    '18': 'البحيرة',
    '19': 'الإسماعيلية',
    '21': 'الجيزة',
    '22': 'بني سويف',
    '23': 'الفيوم',
    '24': 'المنيا',
    '25': 'أسيوط',
    '26': 'سوهاج',
    '27': 'قنا',
    '28': 'أسوان',
    '29': 'الأقصر',
    '31': 'البحر الأحمر',
    '32': 'الوادي الجديد',
    '33': 'مطروح',
    '34': 'شمال سيناء',
    '35': 'جنوب سيناء',
    '88': 'خارج مصر',
  };

  static String? extractGovernorate(String nationalId) {
    if (!RegExp(r'^[23]\d{13}$').hasMatch(nationalId)) return null;
    return _governorates[nationalId.substring(7, 9)];
  }

  static DateTime? birthDateFromNationalId(String nationalId) {
    if (!RegExp(r'^[23]\d{13}$').hasMatch(nationalId)) return null;
    final century = nationalId[0] == '2' ? 1900 : 2000;
    final year = century + int.parse(nationalId.substring(1, 3));
    final month = int.parse(nationalId.substring(3, 5));
    final day = int.parse(nationalId.substring(5, 7));
    final date = DateTime(year, month, day);
    return date.year == year && date.month == month && date.day == day
        ? date
        : null;
  }

  static String? extractArabicName(String text) =>
      _extractFivePartNationalIdName(text) ??
      _extractLabeledValue(text, const [
        'اسم حامل الرخصة',
        'اسم صاحب الرخصة',
        'الاسم الكامل',
        'الاسم',
        'اسم حامل',
      ]);

  static String? extractDrivingLicenseArabicName(String text) {
    final labeledName = _extractLabeledValue(text, const [
      'اسم حامل الرخصة',
      'اسم صاحب الرخصة',
      'الاسم الكامل',
      'الاسم',
    ]);
    if (labeledName != null && _containsArabic(labeledName)) {
      return labeledName;
    }

    final lines = text
        .split(RegExp(r'[\r\n]+'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    final numberLine = lines.indexWhere(
      (line) => RegExp(r'[0-9٠-٩۰-۹]{8,}').hasMatch(line),
    );
    final candidates = numberLine < 0
        ? lines
        : [...lines.skip(numberLine + 1), ...lines.take(numberLine)];
    for (final line in candidates) {
      final words = RegExp(r'[\u0621-\u064A]+')
          .allMatches(line)
          .map((match) => match.group(0)!)
          .where((word) => !_drivingLicenseHeaderWords.contains(word))
          .toList();
      if (words.length >= 3 && words.length <= 6) return words.join(' ');
    }
    return null;
  }

  static String? extractDrivingLicenseEnglishName(String text) {
    const ignoredWords = <String>{
      'arab',
      'arabic',
      'class',
      'department',
      'driving',
      'egypt',
      'expiry',
      'full',
      'government',
      'license',
      'licence',
      'name',
      'nationality',
      'republic',
      'traffic',
    };
    final lines = text.split(RegExp(r'[\r\n]+'));
    for (final line in lines) {
      final words = RegExp(r"[A-Za-z]+(?:['’-][A-Za-z]+)*")
          .allMatches(line)
          .map((match) => match.group(0)!)
          .where((word) {
            return !ignoredWords.contains(
              word.toLowerCase().replaceAll(RegExp(r"['’-]"), ''),
            );
          })
          .toList();
      if (words.length >= 3 && words.length <= 7) return words.join(' ');
    }
    return null;
  }

  static const _drivingLicenseHeaderWords = <String>{
    'جمهورية',
    'مصر',
    'العربية',
    'رخصة',
    'القيادة',
    'الإدارة',
    'الادارة',
    'العامة',
    'لمرور',
    'مرور',
    'القاهرة',
    'وحدة',
    'خدمة',
    'المواطنين',
    'محافظة',
    'المصرية',
    'مصري',
    'مهندس',
    'تاريخ',
    'الميلاد',
    'الدرجة',
    'نوع',
    'الرخصة',
  };

  static bool _containsArabic(String value) =>
      RegExp(r'[\u0621-\u064A]').hasMatch(value);

  static String? _extractFivePartNationalIdName(String text) {
    final marker = RegExp(
      r'بطاق(?:ة|ه)\s*تحق(?:يق|ق)\s*(?:ال)?شخصي(?:ة|ه)',
    ).firstMatch(text);
    if (marker == null) return null;

    final nameLines = text
        .substring(marker.end)
        .split(RegExp(r'[\r\n]+'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .take(2);
    final nameParts = <String>[];
    for (final line in nameLines) {
      final words = RegExp(
        r'[\u0621-\u064A]+',
      ).allMatches(line).map((match) => match.group(0)!).toList();
      nameParts.addAll(
        words.where((word) => !_nationalIdHeaderWords.contains(word)),
      );
    }
    if (nameParts.length < 3) return null;
    return nameParts.join(' ');
  }

  static const _nationalIdHeaderWords = <String>{
    'جمهورية',
    'مصر',
    'العربية',
    'بطاقة',
    'تحقيق',
    'تحقق',
    'الشخصية',
    'شخصية',
    'شخصيه',
  };

  static String? extractExpiryDate(String text) {
    final normalized = normalizeDigits(text);
    final datePattern = RegExp(
      r'(?<!\d)(\d{1,4})\s*[./-]\s*(\d{1,2})\s*[./-]\s*(\d{1,4})(?!\d)',
    );
    final matches = datePattern.allMatches(normalized).toList();
    final candidates = <({DateTime date, bool labeled})>[];
    for (final match in matches) {
      final date = _parseDocumentDate(
        int.parse(match.group(1)!),
        int.parse(match.group(2)!),
        int.parse(match.group(3)!),
      );
      if (date == null) continue;
      final contextStart = (match.start - 40).clamp(0, normalized.length);
      final contextEnd = (match.end + 24).clamp(0, normalized.length);
      final context = normalized.substring(contextStart, contextEnd);
      final labeled = RegExp(
        r'(?:انتهاء|تنتهي|الانتهاء|نهاية\s+الرخصة|الصلاحية|صالحة حتى|سارية حتى|expiry|expires?|valid\s*(?:until|to))',
        caseSensitive: false,
      ).hasMatch(context);
      candidates.add((date: date, labeled: labeled));
    }

    if (candidates.isEmpty) return null;
    final labeledCandidates = candidates.where(
      (candidate) => candidate.labeled,
    );
    final preferred = labeledCandidates.isNotEmpty
        ? labeledCandidates
        : candidates;
    final date = preferred
        .map((candidate) => candidate.date)
        .reduce(
          (latest, candidate) => candidate.isAfter(latest) ? candidate : latest,
        );
    return _formatDocumentDate(date);
  }

  static String? extractVehicleLicenseExpiryDate(String text) {
    final normalized = normalizeDigits(text.replaceAll(RegExp(r'[／⁄]'), '/'));
    final datePattern = RegExp(
      r'(?<!\d)(\d{1,4})\s*[./-]\s*(\d{1,2})\s*[./-]\s*(\d{1,4})(?!\d)',
    );
    final labelPattern = RegExp(
      r'(?:نهاية|انتهاء|انته[تاء])\s*(?:صلاحية\s*)?(?:ال)?(?:رخصة|ترخيص)|صلاحية\s*(?:ال)?(?:رخصة|ترخيص)|expiry|expiration|expires?|valid\s*(?:until|to)',
      caseSensitive: false,
    );
    final dates = datePattern.allMatches(normalized).toList();

    for (final label in labelPattern.allMatches(normalized)) {
      final followingDates = dates.where(
        (date) => date.start >= label.end && date.start - label.end <= 100,
      );
      final following = followingDates.fold<RegExpMatch?>(
        null,
        (closest, date) =>
            closest == null || date.start < closest.start ? date : closest,
      );
      final precedingDates = dates.where(
        (date) => date.end <= label.start && label.start - date.end <= 40,
      );
      final preceding = precedingDates.fold<RegExpMatch?>(
        null,
        (closest, date) =>
            closest == null || date.end > closest.end ? date : closest,
      );
      final target = following ?? preceding;
      if (target == null) continue;
      final parsed = _parseDocumentDate(
        int.parse(target.group(1)!),
        int.parse(target.group(2)!),
        int.parse(target.group(3)!),
      );
      if (parsed != null) return _formatDocumentDate(parsed);
    }

    return extractExpiryDate(normalized);
  }

  static String _formatDocumentDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  static DateTime? _parseDocumentDate(int first, int second, int third) {
    final yearFirst = first > 31;
    final year = yearFirst ? first : (third < 100 ? 2000 + third : third);
    final month = second;
    final day = yearFirst ? third : first;
    final date = DateTime(year, month, day);
    return date.year == year && date.month == month && date.day == day
        ? date
        : null;
  }

  static Map<String, String> extractVehicleDetails(String text) {
    const labels = <String, List<String>>{
      'make': [
        'الشركة المصنعة',
        'الشركة',
        'الماركة',
        'الصانع',
        'manufacturer',
        'make',
      ],
      'model': ['الموديل', 'الطراز', 'model'],
      'year': [
        'سنة التصنيع',
        'سنة الصنع',
        'سنة الموديل',
        'manufacture year',
        'model year',
        'year',
      ],
      'color': ['الألوان', 'اللون', 'colors', 'color'],
      'plate': ['رقم اللوحة', 'رقم السيارة', 'اللوحة', 'plate number', 'plate'],
    };
    final result = <String, String>{};
    for (final entry in labels.entries) {
      final value = _extractLabeledValue(text, entry.value);
      if (value != null) result[entry.key] = value;
    }
    _extractUnlabeledVehicleDetails(text, result);
    final plate = _extractUnlabeledPlate(text);
    if (!result.containsKey('plate') && plate != null) result['plate'] = plate;
    return result;
  }

  static String? _extractUnlabeledPlate(String text) {
    for (final line in text.split(RegExp(r'[\r\n]+'))) {
      if (RegExp(r'[/.\-]').hasMatch(line)) continue;
      final digits = RegExp(
        r'[0-9٠-٩۰-۹]',
      ).allMatches(line).map((match) => match.group(0)!).toList();
      if (digits.length < 3 || digits.length > 4) continue;

      final letterTokens = line
          .split(RegExp(r'[\s،؛:|]+'))
          .map((token) => token.replaceAll(RegExp(r'[^\u0621-\u064A]'), ''))
          .where((token) => token.isNotEmpty && token.length <= 3)
          .expand((token) => token.split(''))
          .toList();
      if (letterTokens.length != 3) continue;

      final firstLetter = line.indexOf(letterTokens.first);
      final firstDigit = RegExp(r'[0-9٠-٩۰-۹]').firstMatch(line)!.start;
      if (firstDigit < firstLetter) {
        letterTokens.setAll(0, letterTokens.reversed.toList());
      }
      return '${letterTokens.join(' ')} ${digits.join()}';
    }
    return null;
  }

  static void _extractUnlabeledVehicleDetails(
    String text,
    Map<String, String> result,
  ) {
    final lines = text
        .split(RegExp(r'[\r\n]+'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    final yearPattern = RegExp(r'(?<!\d)(?:19|20)\d{2}(?!\d)');
    for (final line in lines) {
      final normalizedLine = normalizeDigits(line);
      final dateOrExpiryLine = RegExp(
        r'\d\s*[./-]\s*\d|تاريخ|انتهاء|نهاية|فحص|تحرير',
      ).hasMatch(line);
      if (result['year'] == null && !dateOrExpiryLine) {
        final year = yearPattern.firstMatch(normalizedLine)?.group(0);
        final parsedYear = int.tryParse(year ?? '');
        if (parsedYear != null &&
            parsedYear >= 1980 &&
            parsedYear <= DateTime.now().year) {
          result['year'] = parsedYear.toString();
        }
      }

      final manufacturer = _vehicleManufacturers.firstWhere(
        (name) => line.toLowerCase().contains(name.toLowerCase()),
        orElse: () => '',
      );
      if (manufacturer.isNotEmpty) {
        result.putIfAbsent('make', () => manufacturer);
        if (result['model'] == null) {
          final model = normalizedLine
              .replaceAll(
                RegExp(RegExp.escape(manufacturer), caseSensitive: false),
                ' ',
              )
              .replaceAll(yearPattern, ' ')
              .replaceAllMapped(
                RegExp(r'[\u0621-\u064A]+'),
                (Match match) => _vehicleHeaderWords.contains(match.group(0))
                    ? ' '
                    : match.group(0) ?? '',
              )
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim();
          if (model.isNotEmpty) result['model'] = model;
        }
      }

      if (result['color'] == null) {
        final lineWords = line
            .split(RegExp(r'[\s،؛:]+'))
            .map((word) => word.replaceAll(RegExp(r'[^\u0621-\u064A]'), ''))
            .toSet();
        final colors = _vehicleColors
            .where(lineWords.contains)
            .toSet()
            .toList();
        if (colors.isNotEmpty) result['color'] = colors.join(' و');
      }
    }

    if (result['model'] == null) {
      for (final line in lines) {
        final model = _vehicleModels.firstWhere(
          (name) => line.toLowerCase().contains(name.toLowerCase()),
          orElse: () => '',
        );
        if (model.isNotEmpty) {
          result['model'] = model;
          break;
        }
      }
    }
  }

  static const _vehicleManufacturers = <String>[
    'دايو',
    'تويوتا',
    'هيونداي',
    'شيفروليه',
    'سوزوكي',
    'ميتسوبيشي',
    'نيسان',
    'كيا',
    'فيات',
    'بيجو',
    'مرسيدس',
    'أوبل',
    'BMW',
    'Daewoo',
    'Toyota',
    'Hyundai',
    'Chevrolet',
    'Suzuki',
    'Mitsubishi',
    'Nissan',
    'Kia',
    'Fiat',
    'Peugeot',
    'Mercedes',
    'Opel',
  ];

  static const _vehicleModels = <String>[
    'لانوس',
    'نوبيرا',
    'ماتيز',
    'فيرنا',
    'النترا',
    'أكسنت',
    'افيو',
    'لانسر',
    'صني',
    'كورولا',
    'Lanos',
    'Nubira',
    'Matiz',
    'Verna',
    'Elantra',
    'Accent',
    'Aveo',
    'Lancer',
    'Sunny',
    'Corolla',
  ];

  static const _vehicleColors = <String>[
    'أبيض',
    'ابيض',
    'أسود',
    'اسود',
    'أحمر',
    'احمر',
    'أزرق',
    'ازرق',
    'فضي',
    'فضية',
    'رمادي',
    'رصاصي',
    'ذهبي',
    'ذهبي',
    'أخضر',
    'اخضر',
    'بني',
    'بيج',
  ];

  static const _vehicleHeaderWords = <String>{
    'سيارة',
    'ملاكي',
    'رخصة',
    'الموديل',
    'موديل',
    'صنع',
    'سنة',
    'عام',
  };

  static String? _extractLabeledValue(String text, List<String> labels) {
    final lines = text
        .split(RegExp(r'[\r\n]+'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    final lowerLabels = labels.map((label) => label.toLowerCase()).toList();
    for (var index = 0; index < lines.length; index++) {
      final lowerLine = lines[index].toLowerCase();
      for (final label in lowerLabels) {
        final labelIndex = lowerLine.indexOf(label);
        if (labelIndex < 0) continue;
        final afterLabel = lines[index]
            .substring(labelIndex + label.length)
            .replaceFirst(RegExp(r'^[\s:：\-–]+'), '')
            .trim();
        if (afterLabel.isNotEmpty &&
            !RegExp(r'^(الرخصة|كامل|حامل)[:：\s]*$').hasMatch(afterLabel)) {
          return afterLabel;
        }
        if (index + 1 < lines.length) return lines[index + 1];
      }
    }
    return null;
  }

  static bool isPastDate(String isoDate, {DateTime? today}) {
    final expiry = DateTime.tryParse(isoDate);
    if (expiry == null) return false;
    final current = today ?? DateTime.now();
    return DateTime(
      expiry.year,
      expiry.month,
      expiry.day,
    ).isBefore(DateTime(current.year, current.month, current.day));
  }

  static bool namesMatch(String first, String second) =>
      _normalizeArabicName(first) == _normalizeArabicName(second);

  static String _normalizeArabicName(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[\u064B-\u065F\u0670\u0640]'), '')
      .replaceAll(RegExp(r'[أإآٱ]'), 'ا')
      .replaceAll('ى', 'ي')
      .replaceAll('ة', 'ه')
      .replaceAll(RegExp(r'[^a-z0-9\u0621-\u064A]'), '');

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
    final detectedCandidates = numberPattern
        .allMatches(text)
        .map(
          (match) =>
              normalizeDigits(match.group(0)!.replaceAll(RegExp(r'[\s-]'), '')),
        )
        .toSet();

    if (detectedCandidates.isEmpty) {
      throw const NationalIdOcrException(
        'لم يتم العثور على رقم قومي من 14 رقمًا. اختر صورة أوضح للوجه الأمامي.',
      );
    }
    final candidates = detectedCandidates
        .where((candidate) => birthDateFromNationalId(candidate) != null)
        .toSet();
    if (candidates.isEmpty) {
      throw const NationalIdOcrException(
        'الرقم المستخرج غير صالح أو تاريخ الميلاد فيه غير صحيح. راجع الصورة.',
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
