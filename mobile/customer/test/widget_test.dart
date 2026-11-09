// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:main/main.dart';
import 'package:main/screens/home_screen.dart';
import 'package:main/screens/welcome_screen.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('completing onboarding persists and skips it next launch', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(const MyApp());
    expect(find.text('MAKE LOGISTICS SIMPLE'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Move anything.'), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Find the right truck.'), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Track every move.'), findsOneWidget);
    expect(find.text('Get started'), findsOneWidget);

    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    expect(find.text('One app. Every\nmove.'), findsOneWidget);

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getBool('onboarding_completed'), isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(const MyApp());
    expect(find.text('MAKE LOGISTICS SIMPLE'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('One app. Every\nmove.'), findsOneWidget);
    expect(find.text('Move anything.'), findsNothing);
  });

  testWidgets('Skip marks onboarding complete', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MyApp());
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Move anything.'), findsOneWidget);

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(find.text('One app. Every\nmove.'), findsOneWidget);

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getBool('onboarding_completed'), isTrue);
  });

  testWidgets('email login screen shows the current email and password flow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MaterialApp(home: WelcomeScreen()));
    await tester.tap(find.text('I already have an account'));
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Forgot password?'), findsOneWidget);

    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();

    expect(find.text('Forgot password'), findsOneWidget);
    expect(
      find.text('Enter the email address linked to your account.'),
      findsOneWidget,
    );
  });

  testWidgets('welcome account action navigates through login to sign up', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MaterialApp(home: WelcomeScreen()));
    await tester.tap(find.text('I already have an account'));
    await tester.pumpAndSettle();
    expect(find.text('Welcome back'), findsOneWidget);

    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    expect(find.text("Let's get moving"), findsOneWidget);
    expect(
      find.text('I agree to the Terms and Privacy Policy'),
      findsOneWidget,
    );
  });

  testWidgets('home remains scrollable on a compact viewport', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(home: HomeScreen(isPreview: true)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Welcome'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, -360),
    );
    await tester.pumpAndSettle();
    expect(find.text('Estimate my cargo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('main navigation switches between all existing destinations', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(home: HomeScreen(isPreview: true)),
    );
    await tester.pumpAndSettle();

    final navigation = find.byType(BottomNavigationBar);

    await tester.tap(find.text('Messages').first);
    await tester.pumpAndSettle();
    expect(find.text('No conversations yet'), findsOneWidget);
    expect(tester.widget<BottomNavigationBar>(navigation).currentIndex, 2);

    await tester.tap(find.text('Wallet').first);
    await tester.pumpAndSettle();
    expect(find.text('Available balance'), findsOneWidget);
    expect(find.text('No transactions yet'), findsOneWidget);
    expect(tester.widget<BottomNavigationBar>(navigation).currentIndex, 3);

    await tester.tap(find.text('Profile').first);
    await tester.pump();
    expect(find.text('Profile'), findsNWidgets(2));
    expect(tester.widget<BottomNavigationBar>(navigation).currentIndex, 4);

    await tester.tap(find.text('Trips').first);
    await tester.pump();
    expect(find.text('Recent moves'), findsOneWidget);
    expect(tester.widget<BottomNavigationBar>(navigation).currentIndex, 1);

    await tester.tap(find.text('Home').first);
    await tester.pump();
    expect(find.text('Welcome'), findsOneWidget);
    expect(tester.widget<BottomNavigationBar>(navigation).currentIndex, 0);
    expect(tester.takeException(), isNull);
  });
}
