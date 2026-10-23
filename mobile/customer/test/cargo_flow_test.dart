import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:main/screens/home_screen.dart';

void main() {
  testWidgets('home completes a cargo order through the multi-stop flow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(home: HomeScreen(isPreview: true)),
    );

    final homeFields = find.byType(TextField);
    await tester.enterText(homeFields.at(0), 'Nasr City');
    await tester.enterText(homeFields.at(1), 'Maadi');
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move something'));
    await tester.pumpAndSettle();

    expect(find.text('What are you moving?'), findsOneWidget);
    await tester.tap(find.text('Furniture'));
    await tester.pump();
    expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
    await tester.tap(find.text('Continue').last);
    await tester.pumpAndSettle();

    expect(find.text('Where should we go?'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).at(1), '');
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue').last);
    await tester.pumpAndSettle();
    expect(find.text('Enter a location'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).at(1), 'Maadi');
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add another stop'));
    await tester.pumpAndSettle();
    expect(find.text('Add stops to your route'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).first, 'Heliopolis');
    await tester.tap(find.text('Continue').last);
    await tester.pumpAndSettle();
    expect(find.text('Tell us about your cargo'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).first, 'Two-seat sofa');
    await tester.tap(find.text('Continue to photos'));
    await tester.pumpAndSettle();
    expect(find.text('Add a cargo photo'), findsOneWidget);
    expect(find.text('Extra stops'), findsOneWidget);

    await tester.tap(find.text('Save demo request'));
    await tester.pumpAndSettle();
    expect(find.text('Your activity'), findsOneWidget);
    expect(
      find.text(
        'Demo request saved on this device. No driver has been requested.',
      ),
      findsOneWidget,
    );
    expect(find.text('Nasr City  →  Heliopolis  →  Maadi'), findsOneWidget);
  });
}
