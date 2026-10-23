import 'package:driver/main.dart';
import 'package:driver/screens/driver_application_screen.dart';
import 'package:driver/screens/driver_home_screen.dart';
import 'package:driver/screens/verification_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('welcome opens the seven-step driver application', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const WaslaDriverApp());
    expect(find.text('Drive with Wasla'), findsOneWidget);

    await tester.tap(find.text('Become a driver'));
    await tester.pumpAndSettle();
    expect(find.text('1 OF 7'), findsOneWidget);
    expect(find.text('Let’s meet you'), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('2 OF 7'), findsOneWidget);
    await _addDocuments(tester, [
      'Take photo or upload',
      'Take photo or upload',
    ]);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('3 OF 7'), findsOneWidget);
    expect(find.text('Your driving license'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('application supports document preview interactions', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(home: DriverApplicationScreen(initialStep: 1)),
    );
    await _addDocuments(tester, [
      'Take photo or upload',
      'Take photo or upload',
    ]);
    expect(find.text('Added · local preview only'), findsNWidgets(2));

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('3 OF 7'), findsOneWidget);
    expect(find.text('Your driving license'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('application steps stay usable on a compact screen', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MaterialApp(home: DriverApplicationScreen()));
    for (var step = 0; step < 3; step++) {
      expect(tester.takeException(), isNull);
      if (step == 1) {
        await _addDocuments(tester, [
          'Take photo or upload',
          'Take photo or upload',
        ]);
      } else if (step == 2) {
        await _addDocuments(tester, ['Take photo or upload']);
      }
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
    }
    expect(find.text('4 OF 7'), findsOneWidget);
    expect(find.text('Register your truck'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalid personal details prevent advancing and show errors', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MaterialApp(home: DriverApplicationScreen()));
    await tester.enterText(find.byType(TextFormField).at(0), 'A');
    await tester.enterText(find.byType(TextFormField).at(1), '123');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('1 OF 7'), findsOneWidget);
    expect(find.text('Enter your first and family names.'), findsOneWidget);
    expect(find.text('Enter a valid Egyptian mobile number.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalid national ID and missing photos block next step', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(home: DriverApplicationScreen(initialStep: 1)),
    );
    await tester.enterText(find.byType(TextFormField).first, '1234');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('2 OF 7'), findsOneWidget);
    expect(
      find.text('National ID must contain exactly 14 digits.'),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextFormField).first, '29203121234567');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(
      find.text('Add photos of the front and back of your National ID.'),
      findsOneWidget,
    );
    expect(find.text('3 OF 7'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('payment form validates account holder and IBAN', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(home: DriverApplicationScreen(initialStep: 5)),
    );
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(2), 'EG123');
    await tester.tap(find.text('Save payment details'));
    await tester.pumpAndSettle();
    expect(find.text('6 OF 7'), findsOneWidget);
    expect(
      find.text('Enter a valid Egyptian IBAN (EG followed by 27 digits).'),
      findsOneWidget,
    );

    await tester.enterText(fields.at(2), 'EG380019000500000000263180002');
    await tester.enterText(fields.at(0), 'Different Name');
    await tester.tap(find.text('Save payment details'));
    await tester.pumpAndSettle();
    expect(
      find.text('Account holder must match your legal name.'),
      findsOneWidget,
    );

    await tester.enterText(fields.at(0), 'Ahmed Hassan');
    await tester.tap(find.text('Save payment details'));
    await tester.pumpAndSettle();
    expect(find.text('7 OF 7'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending status links back to document review', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: VerificationScreen(status: VerificationStatus.pending),
      ),
    );
    expect(find.text('Your checks are underway'), findsOneWidget);
    expect(
      find.text(
        'Preview only · Your documents have not been uploaded or submitted.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('View submitted documents'));
    await tester.pumpAndSettle();
    expect(find.text('7 OF 7'), findsOneWidget);
    expect(find.text('Ready for verification?'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('verification outcomes route to their supported next screens', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: VerificationScreen(status: VerificationStatus.rejected),
      ),
    );
    expect(find.text('Let’s fix one document'), findsOneWidget);
    await tester.tap(find.text('Resubmit driving license'));
    await tester.pumpAndSettle();
    expect(find.text('3 OF 7'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      const MaterialApp(
        home: VerificationScreen(status: VerificationStatus.approved),
      ),
    );
    expect(find.text('You’re ready to move'), findsOneWidget);
    await tester.tap(find.text('Go to driver home'));
    await tester.pumpAndSettle();
    expect(find.text('You’re offline'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('driver availability toggle updates the home state', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MaterialApp(home: DriverHomeScreen()));
    expect(find.text('You’re offline'), findsOneWidget);

    await tester.tap(find.text('Go online'));
    await tester.pumpAndSettle();
    expect(find.text('You’re online'), findsOneWidget);
    expect(find.text('Nearby · Nasr City → Maadi · EGP 432'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _addDocuments(WidgetTester tester, List<String> labels) async {
  for (final label in labels) {
    final finder = find.text(label).first;
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }
}
