import 'package:driver/data/driver_api.dart';
import 'package:driver/data/driver_application.dart';
import 'package:driver/main.dart';
import 'package:driver/screens/driver_auth_screen.dart';
import 'package:driver/screens/driver_home_screen.dart';
import 'package:driver/screens/driver_profile_screen.dart';
import 'package:driver/screens/driver_welcome_screen.dart';
import 'package:driver/screens/incoming_request_screen.dart';
import 'package:driver/screens/requests_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('welcome opens driver registration', (tester) async {
    await tester.pumpWidget(const WaslaDriverApp());
    await tester.pumpAndSettle();
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
    await tester.pumpAndSettle();
    await tester.tap(find.text('Already have an account? Log in'));
    await tester.pumpAndSettle();

    expect(find.byType(DriverAuthScreen), findsOneWidget);
    expect(find.text('تسجيل الدخول'), findsOneWidget);
    expect(find.text('إنشاء حساب سائق'), findsNothing);
    expect(find.text('أوافق على الشروط وسياسة الخصوصية'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('chat launcher stays available and opens the driver chat', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const WaslaDriverApp());
    await tester.pumpAndSettle();

    final launcher = find.byKey(const ValueKey('driver-chat-launcher'));
    expect(launcher, findsOneWidget);

    await tester.tap(find.text('Become a driver'));
    await tester.pumpAndSettle();
    expect(launcher, findsOneWidget);

    await tester.tap(launcher);
    await tester.pumpAndSettle();
    expect(find.text('مساعد وصلة'), findsOneWidget);
    expect(
      find.text('نسخة تجريبية — خدمة الرد الذكي غير متصلة بعد.'),
      findsOneWidget,
    );
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

  testWidgets('saved approved driver session resumes at home', (tester) async {
    final api = _FakeDriverApi(hasSession: true, applicationStatus: 'approved');
    await tester.pumpWidget(MaterialApp(home: DriverWelcomeScreen(api: api)));
    await tester.pumpAndSettle();

    expect(find.byType(DriverHomeScreen), findsOneWidget);
    expect(find.text('Drive with Wasla'), findsNothing);
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

    final api = _FakeDriverApi(online: true, testMode: true);
    await tester.pumpWidget(
      MaterialApp(
        home: RequestsListScreen(
          api: api,
          homeBuilder: (_) => DriverHomeScreen(api: api),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('12 Abbas El Akkad → 18 Road 9  ·  EGP 535.65 net'),
      findsOneWidget,
    );
    expect(
      find.text('TEST MODE · compatibility checks disabled'),
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
    expect(
      find.text(
        'TEST MODE: distance, vehicle type, payload, and helper-capacity checks are disabled.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('profile shows backend identity and supports logout', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = _FakeDriverApi(vehiclePlate: '9999');
    await tester.pumpWidget(MaterialApp(home: DriverProfileScreen(api: api)));
    await tester.pumpAndSettle();

    expect(find.text('Mona Adel'), findsOneWidget);
    expect(find.text('mona@example.com'), findsOneWidget);
    expect(find.text('9999'), findsOneWidget);
    expect(find.text('Active vehicle'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log out'));
    await tester.pumpAndSettle();

    expect(api.logoutCalled, isTrue);
    expect(find.byType(DriverWelcomeScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home navigation from requests returns to home, not welcome', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = _FakeDriverApi();
    await tester.pumpWidget(MaterialApp(home: DriverHomeScreen(api: api)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Requests'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();

    expect(find.byType(DriverHomeScreen), findsOneWidget);
    expect(find.text('Drive with Wasla'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

class _FakeDriverApi extends DriverApi {
  _FakeDriverApi({
    this.online = false,
    this.hasSession = false,
    this.applicationStatus = 'not_started',
    this.vehiclePlate = 'ABC 123',
    this.testMode = false,
  });

  final bool online;
  final bool hasSession;
  final String applicationStatus;
  final String vehiclePlate;
  final bool testMode;
  bool logoutCalled = false;

  @override
  Future<bool> hasSavedSession() async => hasSession;

  @override
  Future<DriverApplication> getApplication() async => DriverApplication(
    status: applicationStatus,
    profile: const {},
    documents: const [],
    vehicles: const [],
    payoutAccount: null,
    missing: const [],
  );

  @override
  Future<Map<String, dynamic>> getDriverStatus() async => {
    'online': online,
    'canGoOnline': true,
    'blockers': <String>[],
    'balance': '125.50',
    'vehicle': {
      'id': '4',
      'vehicleTypeId': '2',
      'plateNumber': vehiclePlate,
      'make': 'Wasla',
      'model': 'Truck',
      'color': 'White',
    },
  };

  @override
  Future<Map<String, dynamic>> getMe() async => {
    'user': {
      'id': '12',
      'fullName': 'Mona Adel',
      'email': 'mona@example.com',
      'phone': '+201001234567',
    },
  };

  @override
  Future<void> logout() async {
    logoutCalled = true;
  }

  @override
  Future<Map<String, dynamic>?> getCurrentTrip() async => null;

  @override
  Future<List<Map<String, dynamic>>> getOffers() async => [
    {
      'id': 'offer-41',
      'testMode': testMode,
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
