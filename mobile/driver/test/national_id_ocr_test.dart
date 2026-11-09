import 'dart:convert';

import 'package:driver/data/national_id_ocr.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('NationalIdOcrService', () {
    test('uses OCR.space language autodetection and extracts the ID', () async {
      final service = NationalIdOcrService(
        apiKey: 'test-key',
        client: MockClient((request) async {
          expect(request.headers['apikey'], 'test-key');
          final multipartBody = request.body;
          expect(multipartBody, contains('name="language"\r\n\r\nauto'));
          expect(multipartBody, contains('name="OCREngine"\r\n\r\n2'));
          expect(multipartBody, contains('name="scale"\r\n\r\ntrue'));
          expect(
            multipartBody,
            contains('name="detectOrientation"\r\n\r\ntrue'),
          );
          return http.Response.bytes(
            utf8.encode(
              '{"IsErroredOnProcessing":false,"ParsedResults":[{"ParsedText":"'
              'الرقم القومي ٢٧٧٠٥٢٥٠١٠٥٩٣٨'
              '"}]}',
            ),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );

      expect(
        await service.readNationalId(
          imageBytes: [1, 2, 3],
          filename: 'front.jpg',
        ),
        '27705250105938',
      );
      service.close();
    });

    test('converts Arabic and Persian numerals to English', () {
      expect(
        NationalIdOcrService.normalizeDigits('٢۷٧٠٥٢٥٠١٠٥٩٣٨'),
        '27705250105938',
      );
    });

    test('extracts one Arabic national ID from OCR text', () {
      expect(
        NationalIdOcrService.extractNationalId(
          'الاسم أحمد\nالرقم القومي\n٢٧٧٠٥٢٥٠١٠٥٩٣٨',
        ),
        '27705250105938',
      );
    });

    test('extracts IDs with OCR-inserted spaces and hyphens', () {
      expect(
        NationalIdOcrService.extractNationalId('2770 5250-105938'),
        '27705250105938',
      );
    });

    test('derives birth date and governorate from a national ID', () {
      expect(
        NationalIdOcrService.birthDateFromNationalId('27705250105938'),
        DateTime(1977, 5, 25),
      );
      expect(
        NationalIdOcrService.extractGovernorate('27705250105938'),
        'القاهرة',
      );
    });

    test('extracts Arabic names and compares normalized spellings', () {
      expect(
        NationalIdOcrService.extractArabicName('الاسم: أحمد محمد علي'),
        'أحمد محمد علي',
      );
      expect(
        NationalIdOcrService.extractArabicName(
          'بطاقة تحقيق شخصية\n'
          'أحمد محمد\n'
          'علي حسن إبراهيم\n'
          'الرقم القومي ٢٧٧٠٥٢٥٠١٠٥٩٣٨',
        ),
        'أحمد محمد علي حسن إبراهيم',
      );
      expect(
        NationalIdOcrService.extractArabicName(
          'بطاقة تحقق شخصيه\n'
          'أحمد\n'
          'محمد علي حسن إبراهيم',
        ),
        'أحمد محمد علي حسن إبراهيم',
      );
      expect(
        NationalIdOcrService.extractArabicName(
          'بطاقة تحقيق الشخصية\n'
          'مريم أحمد\n'
          'سارة عبد الله\n'
          'الرقم القومي ٢٧٧٠٥٢٥٠١٠٥٩٣٨',
        ),
        'مريم أحمد سارة عبد الله',
      );
      expect(
        NationalIdOcrService.extractArabicName(
          'بطاقه تحقق شخصيه\n'
          'ليلى\n'
          'سمير محمود حسن\n'
          'منطقة سكنية\n'
          'مدينة - محافظة',
        ),
        'ليلى سمير محمود حسن',
      );
      expect(
        NationalIdOcrService.extractDrivingLicenseArabicName(
          'رخصة القيادة\n'
          'الإدارة العامة لمرور القاهرة\n'
          'رقم الرخصة 12345678901234\n'
          'Abdel Fattah Saeed Hussein Khalil El-Sisi\n'
          'عبدالفتاح سعيد حسين خليل السبسي',
        ),
        'عبدالفتاح سعيد حسين خليل السبسي',
      );
      expect(
        NationalIdOcrService.extractDrivingLicenseEnglishName(
          'EGYPTIAN DRIVING LICENSE\n'
          'Name: Abdel Fattah Saeed Hussein Khalil El-Sisi\n'
          'License number: 123456',
        ),
        'Abdel Fattah Saeed Hussein Khalil El-Sisi',
      );
      final idName = NationalIdOcrService.extractArabicName(
        'بطاقة تحقيق الشخصية\n'
        'عبدالفتاح\n'
        'سعيد حسين خليل السبسي\n'
        'العنوان: القاهرة',
      );
      final licenseName = NationalIdOcrService.extractDrivingLicenseArabicName(
        'DRIVING LICENSE\n'
        'Name: Abdel Fattah Saeed Hussein Khalil El-Sisi\n'
        '2541119010101716\n'
        'عبدالفتاح سعيد حسين خليل السبسي',
      );
      expect(idName, 'عبدالفتاح سعيد حسين خليل السبسي');
      expect(licenseName, 'عبدالفتاح سعيد حسين خليل السبسي');
      expect(NationalIdOcrService.namesMatch(idName!, licenseName!), isTrue);
      expect(
        NationalIdOcrService.namesMatch('أحمد محمد علي', 'احمد محمد على'),
        isTrue,
      );
      expect(
        NationalIdOcrService.namesMatch('أحمد محمد علي', 'محمود محمد علي'),
        isFalse,
      );
    });

    test('extracts document expiry and vehicle registration fields', () {
      expect(
        NationalIdOcrService.extractExpiryDate('تاريخ الانتهاء: ١٢/٠٥/٢٠٢٤'),
        '2024-05-12',
      );
      expect(
        NationalIdOcrService.extractExpiryDate(
          '25/01/1952\n22/01/2023\n21/01/2033',
        ),
        '2033-01-21',
      );
      expect(
        NationalIdOcrService.extractExpiryDate(
          'تاريخ الإصدار 22/01/2023، تاريخ الانتهاء 21/01/2033',
        ),
        '2033-01-21',
      );
      expect(
        NationalIdOcrService.extractExpiryDate(
          'نهاية الرخصة ٢٠١٩/٠١/١٢\nتاريخ التحرير ٢٠١٧/٠١/٣١',
        ),
        '2019-01-12',
      );
      const vehicleLicenseText =
          'نهاية الرخصة . ٢٠١٩/١/١٢\n'
          'تاريخ التحرير ٢٠١٧/١/٣١';
      expect(
        NationalIdOcrService.extractVehicleLicenseExpiryDate(
          vehicleLicenseText,
        ),
        '2019-01-12',
      );
      expect(
        NationalIdOcrService.extractVehicleLicenseExpiryDate(
          'تاريخ الترخيص ٢٠٣٠/٠١/٠١\n'
          'نهاية الرخصة\n'
          '٢٠١٩/٠١/١٢',
        ),
        '2019-01-12',
      );
      expect(
        NationalIdOcrService.extractVehicleLicenseExpiryDate(
          'تاريخ الترخيص ٢٠٣٠/٠١/٠١\n'
          'نهاية الرخصة . ٢٠١٩/١/١٢\n'
          'تاريخ التحرير ٢٠١٧/١/٣١',
        ),
        '2019-01-12',
      );
      expect(
        NationalIdOcrService.extractVehicleLicenseExpiryDate(
          'انتهاء الترخيص ٢٠١٩/١٠/١٢',
        ),
        '2019-10-12',
      );
      expect(
        NationalIdOcrService.isPastDate(
          NationalIdOcrService.extractVehicleLicenseExpiryDate(
            vehicleLicenseText,
          )!,
          today: DateTime(2026, 11, 9),
        ),
        isTrue,
      );
      expect(
        NationalIdOcrService.extractVehicleDetails(
          'نهاية الرخصة ٢٠١٩/٠١/١٢\nتاريخ التحرير ٢٠١٧/٠١/٣١',
        ).containsKey('year'),
        isFalse,
      );
      expect(
        NationalIdOcrService.isPastDate(
          NationalIdOcrService.extractExpiryDate(
            'نهاية الرخصة ٢٠١٩/٠١/١٢\nتاريخ التحرير ٢٠١٧/٠١/٣١',
          )!,
          today: DateTime(2026, 11, 9),
        ),
        isTrue,
      );
      expect(
        NationalIdOcrService.isPastDate(
          '2024-05-12',
          today: DateTime(2024, 5, 13),
        ),
        isTrue,
      );
      expect(
        NationalIdOcrService.extractVehicleDetails(
          'الشركة المصنعة: تويوتا\n'
          'الموديل: هايس\n'
          'سنة الصنع: ٢٠٢٢\n'
          'اللون: أبيض وأزرق\n'
          'رقم اللوحة: س ج م ١٢٣٤',
        ),
        {
          'make': 'تويوتا',
          'model': 'هايس',
          'year': '٢٠٢٢',
          'color': 'أبيض وأزرق',
          'plate': 'س ج م ١٢٣٤',
        },
      );
      expect(
        NationalIdOcrService.extractVehicleDetails(
          'دايو لانوس ٢ ١٩٩٩\n'
          'شاسيه ١٤٧٩٨٥٣\n'
          'موتور ٤٥٦١٢\n'
          '٤ سلندر بنزين ذهبي\n'
          'تاريخ الفحص ٢٠١٩',
        ),
        {'make': 'دايو', 'model': 'لانوس 2', 'year': '1999', 'color': 'ذهبي'},
      );
      expect(NationalIdOcrService.extractVehicleDetails('٤ ٥ ٦ ج ب أ'), {
        'plate': 'أ ب ج ٤٥٦',
      });
      expect(NationalIdOcrService.extractVehicleDetails('أ ب ج ٤٥٦'), {
        'plate': 'أ ب ج ٤٥٦',
      });
    });

    test('matches Arabic manual input with the English OCR result', () {
      expect(
        NationalIdOcrService.matches('٢٧٧٠٥٢٥٠١٠٥٩٣٨', '27705250105938'),
        isTrue,
      );
      expect(
        NationalIdOcrService.matches('27705250105939', '27705250105938'),
        isFalse,
      );
    });

    test('rejects missing and ambiguous national IDs', () {
      expect(
        () => NationalIdOcrService.extractNationalId('لا يوجد رقم في الصورة'),
        throwsA(isA<NationalIdOcrException>()),
      );
      expect(
        () => NationalIdOcrService.extractNationalId(
          '27705250105938\n30010101012345',
        ),
        throwsA(isA<NationalIdOcrException>()),
      );
      expect(
        () => NationalIdOcrService.extractNationalId('29902320105938'),
        throwsA(isA<NationalIdOcrException>()),
      );
    });
  });
}
