import 'package:driver/data/driver_api.dart';
import 'package:driver/main.dart';
import 'package:driver/screens/driver_auth_screen.dart';
import 'package:driver/screens/driver_home_screen.dart';
import 'package:driver/screens/incoming_request_screen.dart';
import 'package:driver/screens/requests_list_screen.dart';
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

  testWidgets('welcome login link opens login without signup fields', (
    tester,
  ) async {
    await tester.pumpWidget(const WaslaDriverApp());
    await tester.tap(find.text('Already have an account? Log in'));
    await tester.pumpAndSettle();

    expect(find.byType(DriverAuthScreen), findsOneWidget);
    expect(find.text('تسجيل الدخول'), findsOneWidget);
    expect(find.text('إنشاء حساب سائق'), findsNothing);
    expect(find.text('أوافق على الشروط وسياسة الخصوصية'), findsNothing);
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

  testWidgets('home displays backend availability and wallet data', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(home: DriverHomeScreen(api: _FakeDriverApi())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Morning, Mona'), findsOneWidget);
    expect(find.text('You’re offline'), findsOneWidget);
    expect(find.text('EGP 125.50'), findsOneWidget);
    expect(find.text('ABC 123'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('request list and request details use backend offer data', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final api = _FakeDriverApi(online: true);
    await tester.pumpWidget(MaterialApp(home: RequestsListScreen(api: api)));
    await tester.pumpAndSettle();

    expect(
      find.text('12 Abbas El Akkad → 18 Road 9  ·  EGP 535.65 net'),
      findsOneWidget,
    );
    final card = find.byKey(const ValueKey('request-offer-41'));
    await tester.ensureVisible(card);
    await tester.tap(card);
    await tester.pumpAndSettle();

    expect(find.byType(IncomingRequestScreen), findsOneWidget);
    expect(find.text('EGP 535.65'), findsOneWidget);
    expect(find.text('Cargo  ·  A sofa and 2 chairs'), findsOneWidget);
    expect(find.text('3 items · 120 kg · 0 helpers'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _FakeDriverApi extends DriverApi {
  _FakeDriverApi({this.online = false});

  final bool online;

  @override
  Future<Map<String, dynamic>> getDriverStatus() async => {
    'online': online,
    'canGoOnline': true,
    'blockers': <String>[],
    'balance': '125.50',
    'vehicle': {'id': '4', 'vehicleTypeId': '2', 'plateNumber': 'ABC 123'},
  };

  @override
  Future<Map<String, dynamic>> getMe() async => {
    'user': {'fullName': 'Mona Adel'},
  };

  @override
  Future<Map<String, dynamic>?> getCurrentTrip() async => null;

  @override
  Future<List<Map<String, dynamic>>> getOffers() async => [
    {
      'id': 'offer-41',
      'secondsLeft': 24,
      'distanceToPickupM': 3120,
      'shipmentId': '12',
      'cargoDescription': 'A sofa and 2 chairs',
      'itemCount': 3,
      'weightKg': 120,
      'pickup': {'address': '12 Abbas El Akkad', 'notes': '3rd floor'},
      'dropoff': {'address': '18 Road 9', 'notes': null},
      'routeDistanceM': 12012,
      'fareAmount': '630.18',
      'commissionAmount': '94.53',
      'driverEarning': '535.65',
      'cashToCollect': '630.18',
    },
  ];

  @override
  void close() {}
}
