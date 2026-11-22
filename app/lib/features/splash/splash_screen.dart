import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/storage/bubble_store.dart';
import '../../core/theme/bubble_theme.dart';
import '../../core/transport/transport_orchestrator.dart';
import '../bubble_visuals/bubble_painter.dart';
import '../home/home_screen.dart';
import '../onboarding/onboarding_screen.dart';

class SplashScreen extends StatefulWidget {
  final BubbleStore store;
  final TransportOrchestrator orchestrator;

  const SplashScreen({
    super.key,
    required this.store,
    required this.orchestrator,
  });

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  int _phase = 0;
  Timer? _t1, _t2, _t3;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    await widget.store.load();
    if (!mounted) return;

    _t1 = Timer(const Duration(milliseconds: 220), () {
      if (mounted) setState(() => _phase = 1);
    });
    _t2 = Timer(const Duration(milliseconds: 1150), () {
      if (mounted) setState(() => _phase = 2);
    });
    _t3 = Timer(const Duration(milliseconds: 2200), _goNext);
  }

  void _goNext() {
    if (!mounted) return;
    final nextPage = widget.store.hasProfile
        ? HomeScreen(store: widget.store, orchestrator: widget.orchestrator)
        : OnboardingScreen(store: widget.store, orchestrator: widget.orchestrator);

    Navigator.of(context).pushReplacement(
      CupertinoPageRoute(builder: (_) => nextPage),
    );
  }

  @override
  void dispose() {
    _t1?.cancel();
    _t2?.cancel();
    _t3?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings(widget.store.language);
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: BubbleTheme.backgroundGradient),
        child: Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 520),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: _phase < 2
                ? AnimatedOpacity(
                    key: const ValueKey('wordmark'),
                    opacity: _phase >= 1 ? 1 : 0,
                    duration: const Duration(milliseconds: 480),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          s.appTitle,
                          style: const TextStyle(
                            fontSize: 48,
                            fontWeight: FontWeight.w200,
                            letterSpacing: 7,
                            color: Color(0xFFD6BCFA),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          s.tagline.toUpperCase(),
                          style: TextStyle(
                            fontSize: 11,
                            letterSpacing: 3.4,
                            color: Colors.white.withValues(alpha: 0.72),
                          ),
                        ),
                      ],
                    ),
                  )
                : const InteractiveBubble(
                    key: ValueKey('hero-bubble'),
                    audioLevel: 0.15,
                    size: 210,
                  ),
          ),
        ),
      ),
    );
  }
}
