import 'package:driver/data/driver_application.dart';
import 'package:driver/main.dart';
import 'package:driver/screens/driver_auth_screen.dart';
import 'package:driver/screens/driver_home_screen.dart';
import 'package:driver/screens/incoming_request_screen.dart';
import 'package:driver/screens/requests_list_screen.dart';
import 'package:driver/screens/driver_verification_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('welcome opens driver registration', (tester) async {
    await tester.pumpWidget(const WaslaDriverApp());
    expect(find.text('Drive with Wasla'), findsOneWidget);

    await tester.tap(find.text('Become a driver'));
    await tester.pumpAndSettle();
    expect(find.byType(DriverAuthScreen), findsOneWidget);
    expect(find.text('إنشاء حساب سائق'), findsOneWidget);
    expect(find.text('أوافق على الشروط وسياسة الخصوصية'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('session recovery can open directly in login mode', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: DriverAuthScreen(startInLogin: true)),
    );

    expect(find.text('تسجيل الدخول'), findsOneWidget);
    expect(find.text('لديك حساب؟ سجّل الدخول'), findsNothing);
    expect(find.text('مستخدم جديد؟ أنشئ حساب سائق'), findsOneWidget);
    expect(find.text('أوافق على الشروط وسياسة الخصوصية'), findsNothing);
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

  testWidgets('requests navigation opens the nearby request list', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MaterialApp(home: DriverHomeScreen()));
    await tester.tap(find.byIcon(Icons.list_alt));
    await tester.pumpAndSettle();

    expect(find.text('Requests near you'), findsOneWidget);
    expect(find.text('Nasr City → Maadi  ·  EGP 432 net'), findsOneWidget);
    expect(find.text('Smart Backhaul · Returning your way'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('request list filters and opens the incoming request preview', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MaterialApp(home: RequestsListScreen()));
    expect(find.text('Heliopolis → New Cairo  ·  EGP 560 net'), findsOneWidget);

    await tester.tap(find.text('Smart Backhaul'));
    await tester.pumpAndSettle();
    expect(find.text('Heliopolis → New Cairo  ·  EGP 560 net'), findsNothing);
    expect(find.text('Nasr City → Maadi  ·  EGP 432 net'), findsOneWidget);

    final requestCard = find.byKey(const ValueKey('request-Nasr City → Maadi'));
    await tester.ensureVisible(requestCard);
    await tester.tap(requestCard);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(IncomingRequestScreen), findsOneWidget);
    expect(find.text('Accept request'), findsOneWidget);
    expect(find.text('Decline'), findsOneWidget);
    expect(find.text('EGP 432'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('accepted request completes trip and returns to requests', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MaterialApp(home: IncomingRequestScreen()));
    await tester.tap(find.text('Accept request'));
    await tester.pumpAndSettle();
    expect(find.text('Navigate to pickup'), findsOneWidget);

    await tester.tap(find.text("I've arrived"));
    await tester.pumpAndSettle();
    expect(find.text('Ready to start the trip'), findsOneWidget);

    await tester.tap(find.text('Start trip'));
    await tester.pumpAndSettle();
    expect(find.text('Confirm a safe delivery'), findsOneWidget);

    await tester.tap(find.text('Complete delivery'));
    await tester.pumpAndSettle();
    expect(find.text('Delivery complete!'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 2200));
    await tester.pumpAndSettle();
    expect(find.text('Requests near you'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('application parser reads nested vehicle documents', () {
    final application = DriverApplication.fromJson({
      'application': {
        'id': 'application-12',
        'status': 'draft',
        'profile': {'cityId': '3', 'nationalIdLast4': '1234'},
        'documents': [
          {'type': 'national_id_front', 'status': 'approved'},
        ],
        'vehicles': [
          {
            'id': 'vehicle-4',
            'vehicleTypeId': '9',
            'documents': [
              {
                'type': 'vehicle_photo_cargo',
                'status': 'pending',
                'url': 'https://example.test/cargo.jpg',
              },
            ],
          },
        ],
        'payoutAccount': {'method': 'wallet', 'accountLast4': '5678'},
        'missing': ['license_too_low'],
      },
    });

    expect(application.status, 'draft');
    expect(application.document('national_id_front')?['status'], 'approved');
    expect(application.document('vehicle_photo_cargo')?['status'], 'pending');
    expect(application.activeVehicle?['id'], 'vehicle-4');
    expect(application.missing, contains('license_too_low'));
  });

  test('complete draft resumes at document review', () {
    final application = DriverApplication(
      status: 'draft',
      profile: const {'activeVehicleId': 'vehicle-1'},
      documents: const [
        {'type': 'profile_photo'},
        {'type': 'national_id_front'},
        {'type': 'national_id_back'},
        {'type': 'driving_license_front'},
        {'type': 'driving_license_back'},
      ],
      vehicles: const [
        {
          'id': 'vehicle-1',
          'documents': [
            {'type': 'vehicle_license_front'},
            {'type': 'vehicle_license_back'},
            {'type': 'vehicle_photo_front'},
            {'type': 'vehicle_photo_side'},
            {'type': 'vehicle_photo_rear'},
            {'type': 'vehicle_photo_cargo'},
          ],
        },
      ],
      payoutAccount: const {'method': 'wallet'},
      missing: const [],
    );

    expect(application.nextStep, 4);
  });

  testWidgets('pending rejected vehicle document offers a replacement', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DriverVerificationScreen(
          application: DriverApplication(
            status: 'pending',
            profile: const {'activeVehicleId': 'vehicle-4'},
            documents: const [],
            vehicles: const [
              {
                'id': 'vehicle-4',
                'documents': [
                  {
                    'type': 'vehicle_license_front',
                    'status': 'rejected',
                    'rejectionCode': 'expiry_unreadable',
                    'rejectionReason': 'Retake in daylight.',
                  },
                ],
              },
            ],
            payoutAccount: null,
            missing: const [],
          ),
        ),
      ),
    );

    expect(find.text('Let’s fix one document'), findsOneWidget);
    expect(find.text('تاريخ الانتهاء مش باين'), findsOneWidget);
    expect(find.text('Retake document'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('final rejection is distinct from a document fix request', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DriverVerificationScreen(
          application: DriverApplication(
            status: 'rejected',
            profile: const {},
            documents: const [],
            vehicles: const [],
            payoutAccount: null,
            missing: const [],
            rejectionReason: 'Application does not meet requirements.',
          ),
        ),
      ),
    );

    expect(find.text('Application rejected'), findsOneWidget);
    expect(
      find.text('Application does not meet requirements.'),
      findsOneWidget,
    );
    expect(find.text('Retake document'), findsNothing);
    expect(find.text('Refresh status'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('other rejection reason is displayed once', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DriverVerificationScreen(
          application: DriverApplication(
            status: 'pending',
            profile: const {},
            documents: const [
              {
                'type': 'national_id_back',
                'status': 'rejected',
                'rejectionCode': 'other',
                'rejectionReason': 'The document edges are cut off.',
              },
            ],
            vehicles: const [],
            payoutAccount: null,
            missing: const [],
          ),
        ),
      ),
    );

    expect(find.text('The document edges are cut off.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
