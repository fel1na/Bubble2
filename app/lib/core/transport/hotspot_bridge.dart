import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class HotspotCredentials {
  final String ssid;
  final String password;
  final String ip;

  const HotspotCredentials({
    required this.ssid,
    required this.password,
    required this.ip,
  });
}

/// Dart bridge for Android LocalOnlyHotspot (programmatic local Wi-Fi AP without SIM/data).
class HotspotBridge {
  static const MethodChannel _channel = MethodChannel('com.bubble/hotspot');

  bool get isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<HotspotCredentials?> startHotspot() async {
    if (!isAndroid) return null;
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>('startHotspot');
      if (res == null) return null;
      return HotspotCredentials(
        ssid: res['ssid']?.toString() ?? 'BubbleHotspot',
        password: res['password']?.toString() ?? '',
        ip: res['ip']?.toString() ?? '192.168.43.1',
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> stopHotspot() async {
    if (!isAndroid) return;
    try {
      await _channel.invokeMethod('stopHotspot');
    } catch (_) {}
  }

  Future<String?> getLocalIpAddress() async {
    if (!isAndroid) return null;
    try {
      return await _channel.invokeMethod<String>('getLocalIpAddress');
    } catch (_) {
      return null;
    }
  }
}
