import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/storage/bubble_store.dart';
import '../../core/theme/bubble_theme.dart';
import '../../core/transport/transport_orchestrator.dart';
import '../bubble_visuals/bubble_painter.dart';
import '../common/glass_surface.dart';
import '../home/home_screen.dart';

class OnboardingScreen extends StatefulWidget {
  final BubbleStore store;
  final TransportOrchestrator orchestrator;

  const OnboardingScreen({
    super.key,
    required this.store,
    required this.orchestrator,
  });

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = TextEditingController();
  bool _canContinue = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    HapticFeedback.mediumImpact();
    await widget.store.setNickname(name);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      CupertinoPageRoute(
        builder: (_) => HomeScreen(
          store: widget.store,
          orchestrator: widget.orchestrator,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings(widget.store.language);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: BubbleTheme.backgroundGradient),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              children: [
                const Spacer(),
                const InteractiveBubble(audioLevel: 0.12, size: 170),
                const SizedBox(height: 16),
                Text(
                  s.welcomeTitle,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  s.welcomeSubtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withValues(alpha: 0.65),
                  ),
                ),
                const Spacer(),
                GlassSurface(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        s.nicknamePrompt,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      CupertinoTextField(
                        controller: _controller,
                        autofocus: true,
                        placeholder: s.nicknameHint,
                        placeholderStyle: TextStyle(
                          color: Colors.white.withValues(alpha: 0.35),
                        ),
                        style: const TextStyle(color: Colors.white, fontSize: 16),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                        ),
                        onChanged: (val) => setState(() => _canContinue = val.trim().isNotEmpty),
                        onSubmitted: (_) => _submit(),
                      ),
                      const SizedBox(height: 14),
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        onPressed: _canContinue ? _submit : null,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          height: 50,
                          decoration: BoxDecoration(
                            gradient: _canContinue ? BubbleTheme.primaryGradient : null,
                            color: _canContinue ? null : Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            s.continueBtn,
                            style: TextStyle(
                              color: _canContinue
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.4),
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
