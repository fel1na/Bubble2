import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../core/models/bubble_group.dart';
import '../../core/theme/bubble_theme.dart';
import '../common/glass_surface.dart';

/// Fullscreen Apple-style camera QR scanner for joining a Bubble.
/// Returns a parsed [BubbleInvitePayload] when a valid Bubble QR code is detected.
class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
  );

  bool _handled = false;
  bool _torchOn = false;
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null || raw.isEmpty) continue;

      final parsed = BubbleGroup.parseQrOrLink(raw);
      if (parsed != null) {
        _handled = true;
        HapticFeedback.mediumImpact();
        Navigator.of(context).pop(parsed);
        return;
      } else {
        setState(() {
          _errorText = 'QR non valido. Inquadra un QR code Bubble.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scanSize = MediaQuery.of(context).size.width * 0.68;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),

          // Darkened vignette around center viewfinder
          ColorFiltered(
            colorFilter: ColorFilter.mode(
              Colors.black.withValues(alpha: 0.58),
              BlendMode.srcOut,
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(
                  decoration: const BoxDecoration(
                    color: Colors.black,
                    backgroundBlendMode: BlendMode.dstOut,
                  ),
                ),
                Center(
                  child: Container(
                    width: scanSize,
                    height: scanSize,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Glowing Apple-style frame around viewfinder
          Center(
            child: Container(
              width: scanSize,
              height: scanSize,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: BubbleTheme.primaryViolet.withValues(alpha: 0.85),
                  width: 2.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: BubbleTheme.primaryViolet.withValues(alpha: 0.28),
                    blurRadius: 28,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
          ),

          // Top bar (Close + Torch)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: const GlassSurface(
                          borderRadius: 99,
                          padding: EdgeInsets.all(12),
                          child: Icon(CupertinoIcons.xmark, size: 18, color: Colors.white),
                        ),
                      ),
                      GestureDetector(
                        onTap: () async {
                          await _controller.toggleTorch();
                          if (mounted) setState(() => _torchOn = !_torchOn);
                        },
                        child: GlassSurface(
                          borderRadius: 99,
                          padding: const EdgeInsets.all(12),
                          tint: _torchOn
                              ? BubbleTheme.primaryViolet.withValues(alpha: 0.35)
                              : null,
                          child: Icon(
                            _torchOn ? CupertinoIcons.bolt_fill : CupertinoIcons.bolt,
                            size: 18,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),

                  // Bottom instruction / feedback pill
                  Padding(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: GlassSurface(
                      borderRadius: 99,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _errorText != null
                                ? CupertinoIcons.exclamationmark_triangle
                                : CupertinoIcons.qrcode_viewfinder,
                            size: 16,
                            color: _errorText != null
                                ? BubbleTheme.dangerRed
                                : BubbleTheme.accentMagenta,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _errorText ?? 'Inquadra il QR code della Bubble',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
