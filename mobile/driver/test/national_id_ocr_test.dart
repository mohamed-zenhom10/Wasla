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
    });
  });
}
