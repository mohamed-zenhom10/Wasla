import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:main/pages/cargo_category_page.dart';
import 'package:main/services/auth_service.dart';
import 'package:main/services/cargo_order_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    AuthService.replaceHttpClientForTesting(
      http_testing.MockClient((request) async {
        if (request.url.path == '/api/catalog') {
          return http.Response(
            jsonEncode({
              'cargoCategories': [
                {'id': '1', 'nameEn': 'Furniture', 'sizes': []},
              ],
              'vehicleTypes': [],
              'settings': {'minScheduleLeadMinutes': 30},
            }),
            200,
          );
        }
        return http.Response('{}', 404);
      }),
    );
  });

  testWidgets('cargo category buttons update selection and continue', (tester) async {
    final draft = CargoOrderDraft();
    await tester.pumpWidget(MaterialApp(home: CargoCategoryPage(draft: draft)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Furniture'));
    await tester.pumpAndSettle();

    expect(draft.categoryId, '1');
    expect(find.text('Furniture'), findsOneWidget);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Drop-off location'), findsOneWidget);
  });

  testWidgets('renders the arabic category name for the arabic language preference', (tester) async {
    AuthService.replaceHttpClientForTesting(
      http_testing.MockClient((request) async {
        return http.Response(
          jsonEncode({
            'cargoCategories': [
              {
                'id': '1',
                'code': 'furniture',
                'nameAr': '\u0623\u062B\u0627\u062B',
                'nameEn': 'Furniture',
                'sortOrder': 1,
                'isActive': true,
                'sizes': [
                  {
                    'id': '3',
                    'categoryId': '1',
                    'code': 'few_items',
                    'nameAr': '\u0642\u0637\u0639 \u0642\u0644\u064a\u0644\u0629',
                    'nameEn': 'A few items',
                    'approxVolumeM3': 2,
                    'sortOrder': 1,
                    'isActive': true,
                  },
                ],
              },
            ],
            'vehicleTypes': [],
            'settings': {'minScheduleLeadMinutes': 30},
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    SharedPreferences.setMockInitialValues({
      'profile_language': '\u0627\u0644\u0639\u0631\u0628\u064a\u0629 \u2014 \u0645\u0635\u0631',
    });
    final draft = CargoOrderDraft();
    await tester.pumpWidget(MaterialApp(home: CargoCategoryPage(draft: draft)));
    await tester.pumpAndSettle();

    expect(find.text('\u0623\u062B\u0627\u062B'), findsOneWidget);
  });

  testWidgets('keeps size selection optional for categories without sizes', (tester) async {
    final draft = CargoOrderDraft();
    await tester.pumpWidget(MaterialApp(home: CargoCategoryPage(draft: draft)));
    await tester.pumpAndSettle();

    expect(find.text('Choose this category'), findsOneWidget);

    await tester.tap(find.text('Furniture'));
    await tester.pumpAndSettle();

    expect(draft.categoryId, '1');
    expect(draft.sizeOptionId, isNull);
    expect(draft.category, 'Furniture');

    await tester.tap(find.widgetWithText(ElevatedButton, 'Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Drop-off location'), findsOneWidget);
  });
}
