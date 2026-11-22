import 'package:bubble/core/storage/bubble_store.dart';
import 'package:bubble/core/transport/transport_orchestrator.dart';
import 'package:bubble/features/onboarding/onboarding_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('OnboardingScreen renders Bubble welcome flow', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = BubbleStore();
    await store.load();
    final orchestrator = TransportOrchestrator();

    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingScreen(store: store, orchestrator: orchestrator),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Benvenuto su Bubble'), findsOneWidget);
    orchestrator.dispose();
    store.dispose();
  });
}
