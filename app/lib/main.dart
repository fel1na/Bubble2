import 'package:flutter/material.dart';
import 'core/storage/bubble_store.dart';
import 'core/theme/bubble_theme.dart';
import 'core/transport/transport_orchestrator.dart';
import 'features/splash/splash_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BubbleApp());
}

class BubbleApp extends StatefulWidget {
  const BubbleApp({super.key});

  @override
  State<BubbleApp> createState() => _BubbleAppState();
}

class _BubbleAppState extends State<BubbleApp> {
  final BubbleStore _store = BubbleStore();
  final TransportOrchestrator _orchestrator = TransportOrchestrator();

  @override
  void dispose() {
    _orchestrator.dispose();
    _store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bubble',
      debugShowCheckedModeBanner: false,
      theme: BubbleTheme.buildMaterialTheme(),
      home: SplashScreen(
        store: _store,
        orchestrator: _orchestrator,
      ),
    );
  }
}
