import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Dart bridge for iOS/iPadOS Apple MultipeerConnectivity + AVAudioSession VoIP mode.
class MultipeerBridge {
  static const MethodChannel _channel = MethodChannel('com.bubble/multipeer');
  static const EventChannel _events = EventChannel('com.bubble/multipeer_events');
  static const MethodChannel _audioChannel = MethodChannel('com.bubble/audio_session');

  StreamSubscription<dynamic>? _sub;
  final StreamController<Map<String, dynamic>> _eventController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get events => _eventController.stream;

  bool get isSupported =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.iOS);

  void ensureListening() {
    if (!isSupported || _sub != null) return;
    _sub = _events.receiveBroadcastStream().listen(
      (event) {
        if (event is Map) {
          _eventController.add(Map<String, dynamic>.from(event));
        }
      },
      onError: (_) {},
    );
  }

  Future<bool> activateVoiceAudioSession() async {
    if (!isSupported) return true;
    try {
      return await _audioChannel.invokeMethod<bool>('activateVoiceSession') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> deactivateVoiceAudioSession() async {
    if (!isSupported) return;
    try {
      await _audioChannel.invokeMethod('deactivateVoiceSession');
    } catch (_) {}
  }

  Future<void> startNearbyScan({required String displayName}) async {
    if (!isSupported) return;
    ensureListening();
    try {
      await _channel.invokeMethod('startNearbyScan', {'displayName': displayName});
    } catch (_) {}
  }

  Future<void> stopNearbyScan() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod('stopNearbyScan');
    } catch (_) {}
  }

  Future<void> startRoomSession({
    required String roomCode,
    required String roomName,
    required String displayName,
  }) async {
    if (!isSupported) return;
    ensureListening();
    await _channel.invokeMethod('startRoomSession', {
      'roomCode': roomCode,
      'roomName': roomName,
      'displayName': displayName,
    });
  }

  Future<void> sendJson(Map<String, dynamic> payload, {bool reliable = true}) async {
    if (!isSupported) return;
    await _channel.invokeMethod('sendMessage', {
      'message': jsonEncode(payload),
      'reliable': reliable,
    });
  }

  Future<void> stopSession() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod('stopSession');
    } catch (_) {}
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
    _eventController.close();
  }
}
