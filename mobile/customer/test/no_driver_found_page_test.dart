import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:main/models/shipment.dart';
import 'package:main/pages/no_driver_found_page.dart';

void main() {
  testWidgets('NoDriverFoundPage shows cancellation details and retry callback', (tester) async {
    var retried = false;
    await tester.pumpWidget(
      MaterialApp(
        home: NoDriverFoundPage(
          shipment: Shipment.fromJson({
            'id': '12',
            'status': 'cancelled',
            'cancellationParty': 'platform',
            'cancellationReason': 'no_driver_found',
          }),
          onTryAgain: () => retried = true,
        ),
      ),
    );

    expect(find.text('No driver found'), findsOneWidget);
    expect(find.text('Try Again'), findsOneWidget);
    await tester.tap(find.text('Try Again'));
    expect(retried, isTrue);
  });
}
