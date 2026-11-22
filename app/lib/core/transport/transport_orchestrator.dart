import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/bubble_group.dart';
import '../models/peer_participant.dart';
import 'hotspot_bridge.dart';
import 'local_ws_server.dart';
import 'multipeer_bridge.dart';
import 'rtc_mesh_engine.dart';

/// Offline-first connection cascade orchestrator:
/// 1. Local LAN / Hotspot WebSocket + Offline ICE (0 external servers)
/// 2. Apple MultipeerConnectivity on iOS / iPadOS (BLE + Wi-Fi AWDL)
/// 3. Independent self-hosted Server fallback (Internet 4G/5G/Wi-Fi)
class TransportOrchestrator extends ChangeNotifier {
  final LocalWsServer _localWsServer = LocalWsServer();
  final MultipeerBridge _multipeer = MultipeerBridge();
  final HotspotBridge _hotspot = HotspotBridge();

  TransportMode _mode = TransportMode.idle;
  String? _localQrEndpointUrl;
  String? _hotspotSsid;
  String? _hotspotPassword;
  String? _errorMessage;

  final Map<String, PeerParticipant> _participants = {};
  final Map<String, NearbyBubbleDiscovery> _nearby = {};

  WebSocketChannel? _remoteWs;
  StreamSubscription<dynamic>? _remoteWsSub;
  StreamSubscription<Map<String, dynamic>>? _localWsSub;
  StreamSubscription<Map<String, dynamic>>? _multipeerSub;
  StreamSubscription<double>? _audioLevelSub;

  RtcMeshEngine? _rtc;
  double _localAudioLevel = 0;
  bool _isMuted = false;

  String? _activeRoomCode;
  String? _localPeerId;
  String? _localDisplayName;
  bool _isHost = false;

  TransportMode get mode => _mode;
  String? get localQrEndpointUrl => _localQrEndpointUrl;
  String? get hotspotSsid => _hotspotSsid;
  String? get hotspotPassword => _hotspotPassword;
  String? get errorMessage => _errorMessage;
  bool get isMuted => _isMuted;
  double get localAudioLevel => _localAudioLevel;
  List<PeerParticipant> get participants => _participants.values.toList();
  List<NearbyBubbleDiscovery> get nearbyBubbles => _nearby.values.toList();
  bool get isLive =>
      _mode != TransportMode.idle && _mode != TransportMode.connecting;

  void startNearbyDiscovery({required String displayName}) {
    if (_multipeer.isSupported) {
      _multipeerSub ??= _multipeer.events.listen(_handleMultipeerEvent);
      _multipeer.startNearbyScan(displayName: displayName);
    }
  }

  void stopNearbyDiscovery() {
    _multipeer.stopNearbyScan();
  }

  Future<void> startSession({
    required BubbleGroup group,
    required String localPeerId,
    required String displayName,
    required String internetWsUrl,
    String? directLocalWsUrl,
    bool preferHotspot = false,
  }) async {
    await stopSession();

    _activeRoomCode = group.code;
    _localPeerId = localPeerId;
    _localDisplayName = displayName;
    _errorMessage = null;
    _setMode(TransportMode.connecting);

    await _multipeer.activateVoiceAudioSession();

    // Step 1: Direct local endpoint from scanned QR / LAN discovery
    if (directLocalWsUrl != null && directLocalWsUrl.isNotEmpty) {
      final ok = await _tryConnectWs(
        wsUrl: directLocalWsUrl,
        roomCode: group.code,
        offlineIce: true,
        targetMode: TransportMode.offlineLan,
      );
      if (ok) return;
    }

    // Step 2: Start local LAN / Hotspot host server + Apple Multipeer P2P in parallel
    final localPort = await _localWsServer.start();
    String? ip = await LocalWsServer.resolveLocalIpv4();

    if (preferHotspot && _hotspot.isAndroid) {
      final creds = await _hotspot.startHotspot();
      if (creds != null) {
        _hotspotSsid = creds.ssid;
        _hotspotPassword = creds.password;
        ip = creds.ip;
      }
    }

    if (ip != null) {
      _localQrEndpointUrl = 'ws://$ip:$localPort';
    }

    if (_multipeer.isSupported) {
      _multipeerSub ??= _multipeer.events.listen(_handleMultipeerEvent);
      await _multipeer.startRoomSession(
        roomCode: group.code,
        roomName: group.name,
        displayName: displayName,
      );
    }

    // Listen for local LAN guests joining our local WS server
    _isHost = true;
    await _initRtc(offlineIce: true);
    _localWsSub = _localWsServer.messages.listen(_handleLocalServerMessage);

    if (_multipeer.isSupported) {
      _setMode(TransportMode.offlineMultipeer);
    } else if (_hotspotSsid != null) {
      _setMode(TransportMode.offlineHotspot);
    } else {
      _setMode(TransportMode.offlineLan);
    }

    // Step 3: Optional non-blocking Internet fallback registration if reachable
    _tryAttachInternetFallback(
      internetWsUrl: internetWsUrl,
      roomCode: group.code,
    );
  }

  Future<void> connectInternetFallback({
    required BubbleGroup group,
    required String localPeerId,
    required String displayName,
    required String internetWsUrl,
  }) async {
    await stopSession();
    _activeRoomCode = group.code;
    _localPeerId = localPeerId;
    _localDisplayName = displayName;
    _setMode(TransportMode.connecting);
    await _multipeer.activateVoiceAudioSession();

    final ok = await _tryConnectWs(
      wsUrl: internetWsUrl,
      roomCode: group.code,
      offlineIce: false,
      targetMode: TransportMode.onlineServer,
    );
    if (!ok) {
      _errorMessage = 'Server di fallback non raggiungibile.';
      _setMode(TransportMode.idle);
    }
  }

  Future<void> _tryAttachInternetFallback({
    required String internetWsUrl,
    required String roomCode,
  }) async {
    // Only attach if offline peers haven't connected yet and internet WS is reachable
    try {
      final uri = Uri.parse(internetWsUrl);
      if (uri.host.isEmpty) return;
      final channel = WebSocketChannel.connect(uri);
      await channel.ready.timeout(const Duration(seconds: 3));

      // Keep local mode if local peers already joined; otherwise stay ready on fallback
      if (_participants.isNotEmpty) {
        await channel.sink.close();
        return;
      }

      _remoteWs = channel;
      _remoteWsSub = channel.stream.listen(
        (raw) => _handleRemoteServerMessage(jsonDecode(raw.toString()) as Map<String, dynamic>),
        onError: (_) {},
        onDone: () {},
      );
      _sendWs(channel, {
        'type': 'join',
        'roomCode': roomCode,
        'from': _localPeerId,
        'displayName': _localDisplayName,
        'isMuted': _isMuted,
      });
    } catch (_) {
      // Expected when completely offline (mountains / airplane / no cell service)
    }
  }

  Future<bool> _tryConnectWs({
    required String wsUrl,
    required String roomCode,
    required bool offlineIce,
    required TransportMode targetMode,
  }) async {
    try {
      final channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      await channel.ready.timeout(const Duration(seconds: 4));
      _remoteWs = channel;
      _isHost = false;

      await _initRtc(offlineIce: offlineIce);
      _remoteWsSub = channel.stream.listen(
        (raw) => _handleRemoteServerMessage(jsonDecode(raw.toString()) as Map<String, dynamic>),
        onError: (_) => _onDisconnected(),
        onDone: _onDisconnected,
      );

      _sendWs(channel, {
        'type': 'join',
        'roomCode': roomCode,
        'from': _localPeerId,
        'displayName': _localDisplayName,
        'isMuted': _isMuted,
      });

      _setMode(targetMode);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _initRtc({required bool offlineIce}) async {
    await _rtc?.dispose();
    _audioLevelSub?.cancel();

    final engine = RtcMeshEngine(
      localPeerId: _localPeerId!,
      sendSignal: _dispatchSignal,
    );
    await engine.startMicrophone(offlineMode: offlineIce);
    engine.setMuted(_isMuted);

    _audioLevelSub = engine.audioLevels.listen((lvl) {
      _localAudioLevel = lvl;
      notifyListeners();
    });
    _rtc = engine;
  }

  Future<void> _dispatchSignal(Map<String, dynamic> msg) async {
    final enriched = {
      ...msg,
      'roomCode': _activeRoomCode,
    };

    if (_remoteWs != null) {
      _sendWs(_remoteWs!, enriched);
    }

    if (_isHost && _localWsServer.isRunning) {
      final to = enriched['to']?.toString();
      if (to != null && to.isNotEmpty) {
        _localWsServer.sendToPeer(to, enriched);
      } else {
        _localWsServer.broadcast(enriched, exceptPeerId: _localPeerId);
      }
    }

    if (_multipeer.isSupported) {
      await _multipeer.sendJson(enriched);
    }
  }

  void _handleLocalServerMessage(Map<String, dynamic> msg) {
    final type = msg['type']?.toString();
    final from = msg['from']?.toString();

    if (type == 'join' && from != null && from != _localPeerId) {
      final name = msg['displayName']?.toString() ?? 'Guest';
      final existing = <Map<String, dynamic>>[
        ..._participants.values.map(
          (p) => {'peerId': p.peerId, 'displayName': p.displayName, 'isMuted': p.isMuted},
        ),
        {
          'peerId': _localPeerId,
          'displayName': _localDisplayName,
          'isMuted': _isMuted,
        },
      ];

      _localWsServer.sendToPeer(from, {
        'type': 'joined',
        'roomCode': _activeRoomCode,
        'peerId': from,
        'peers': existing,
      });
      _localWsServer.broadcast({
        'type': 'peer_joined',
        'roomCode': _activeRoomCode,
        'peer': {'peerId': from, 'displayName': name, 'isMuted': msg['isMuted'] == true},
      }, exceptPeerId: from);

      _addOrUpdateParticipant(from, name, isMuted: msg['isMuted'] == true);
      _rtc?.connectPeer(from);
      return;
    }

    final to = msg['to']?.toString();
    if (to != null && to.isNotEmpty && to != _localPeerId) {
      _localWsServer.sendToPeer(to, msg);
      return;
    }

    if (type == 'peer_left') {
      final peerId = msg['peerId']?.toString();
      if (peerId != null) {
        _participants.remove(peerId);
        _rtc?.removePeer(peerId);
        notifyListeners();
      }
      return;
    }

    _rtc?.handleIncomingSignal(msg);
  }

  void _handleRemoteServerMessage(Map<String, dynamic> msg) {
    final type = msg['type']?.toString();

    if (type == 'joined') {
      final peers = (msg['peers'] as List<dynamic>? ?? const []);
      if (peers.isNotEmpty && _mode != TransportMode.offlineLan && _remoteWs != null) {
        // If remote server delivered peers while offline had none, reflect online mode
        if (_participants.isEmpty && _mode != TransportMode.offlineMultipeer) {
          _setMode(TransportMode.onlineServer);
        }
      }
      for (final rawPeer in peers) {
        if (rawPeer is Map) {
          final id = rawPeer['peerId']?.toString();
          if (id != null && id != _localPeerId) {
            _addOrUpdateParticipant(
              id,
              rawPeer['displayName']?.toString() ?? 'Guest',
              isMuted: rawPeer['isMuted'] == true,
            );
            _rtc?.connectPeer(id);
          }
        }
      }
      return;
    }

    if (type == 'peer_joined') {
      final peer = msg['peer'];
      if (peer is Map) {
        final id = peer['peerId']?.toString();
        if (id != null && id != _localPeerId) {
          _addOrUpdateParticipant(
            id,
            peer['displayName']?.toString() ?? 'Guest',
            isMuted: peer['isMuted'] == true,
          );
          _rtc?.connectPeer(id);
        }
      }
      return;
    }

    if (type == 'peer_left') {
      final id = msg['peerId']?.toString();
      if (id != null) {
        _participants.remove(id);
        _rtc?.removePeer(id);
        notifyListeners();
      }
      return;
    }

    if (type == 'mute_state') {
      final id = msg['peerId']?.toString();
      if (id != null && _participants.containsKey(id)) {
        _participants[id] = _participants[id]!.copyWith(isMuted: msg['isMuted'] == true);
        notifyListeners();
      }
      return;
    }

    _rtc?.handleIncomingSignal(msg);
  }

  void _handleMultipeerEvent(Map<String, dynamic> event) {
    final type = event['type']?.toString();

    if (type == 'nearby_found') {
      final code = event['roomCode']?.toString() ?? '';
      if (code.isNotEmpty) {
        _nearby[code] = NearbyBubbleDiscovery(
          roomCode: code,
          roomName: event['roomName']?.toString() ?? 'Bubble #$code',
          hostName: event['hostName']?.toString() ?? 'iPhone',
          source: 'multipeer',
        );
        notifyListeners();
      }
      return;
    }

    if (type == 'peer_state') {
      final state = event['state']?.toString();
      final peerName = event['peerName']?.toString() ?? 'Peer';
      if (state == 'connected') {
        _setMode(TransportMode.offlineMultipeer);
        _multipeer.sendJson({
          'type': 'mp_hello',
          'from': _localPeerId,
          'displayName': _localDisplayName,
          'isMuted': _isMuted,
        });
        _addOrUpdateParticipant('mp_$peerName', peerName);
      } else if (state == 'disconnected') {
        _participants.remove('mp_$peerName');
        notifyListeners();
      }
      return;
    }

    if (type == 'message') {
      final raw = event['message']?.toString();
      if (raw == null) return;
      try {
        final msg = jsonDecode(raw) as Map<String, dynamic>;
        if (msg['type'] == 'mp_hello') {
          final id = msg['from']?.toString();
          if (id != null && id != _localPeerId) {
            _addOrUpdateParticipant(
              id,
              msg['displayName']?.toString() ?? 'Guest',
              isMuted: msg['isMuted'] == true,
            );
            _rtc?.connectPeer(id);
          }
          return;
        }
        _rtc?.handleIncomingSignal(msg);
      } catch (_) {}
    }
  }

  void _addOrUpdateParticipant(String peerId, String name, {bool isMuted = false}) {
    _participants[peerId] = PeerParticipant(
      peerId: peerId,
      displayName: name,
      isMuted: isMuted,
    );
    notifyListeners();
  }

  void toggleMute() {
    _isMuted = !_isMuted;
    _rtc?.setMuted(_isMuted);
    _dispatchSignal({
      'type': 'mute_state',
      'from': _localPeerId,
      'isMuted': _isMuted,
    });
    notifyListeners();
  }

  void _sendWs(WebSocketChannel channel, Map<String, dynamic> data) {
    try {
      channel.sink.add(jsonEncode(data));
    } catch (_) {}
  }

  void _onDisconnected() {
    if (_mode == TransportMode.onlineServer) {
      _setMode(TransportMode.idle);
    }
  }

  void _setMode(TransportMode next) {
    _mode = next;
    notifyListeners();
  }

  Future<void> stopSession() async {
    _audioLevelSub?.cancel();
    _audioLevelSub = null;

    if (_remoteWs != null && _localPeerId != null) {
      _sendWs(_remoteWs!, {
        'type': 'leave',
        'roomCode': _activeRoomCode,
        'from': _localPeerId,
      });
    }

    await _remoteWsSub?.cancel();
    _remoteWsSub = null;
    await _remoteWs?.sink.close().catchError((_) {});
    _remoteWs = null;

    await _localWsSub?.cancel();
    _localWsSub = null;
    await _localWsServer.stop();

    await _multipeer.stopSession();
    await _multipeer.deactivateVoiceAudioSession();
    await _hotspot.stopHotspot();

    await _rtc?.dispose();
    _rtc = null;

    _participants.clear();
    _localAudioLevel = 0;
    _localQrEndpointUrl = null;
    _hotspotSsid = null;
    _hotspotPassword = null;
    _isHost = false;
    _setMode(TransportMode.idle);
  }

  @override
  void dispose() {
    _multipeerSub?.cancel();
    _multipeer.dispose();
    stopSession();
    super.dispose();
  }
}
