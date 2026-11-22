import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';

typedef SendSignalFn = Future<void> Function(Map<String, dynamic> message);

class _PeerEntry {
  final RTCPeerConnection pc;
  final List<RTCIceCandidate> pendingCandidates = [];
  bool remoteDescriptionSet = false;

  _PeerEntry(this.pc);
}

/// Deterministic WebRTC audio mesh for 2-8 participants.
/// Fixes the offer-glare bug from Bubble v1 by letting only the lexicographically
/// smaller peerId initiate the offer (`localId.compareTo(remoteId) < 0`).
class RtcMeshEngine {
  final String localPeerId;
  final SendSignalFn sendSignal;
  final void Function(String peerId, RTCPeerConnectionState state)? onPeerConnectionState;

  final Map<String, _PeerEntry> _peers = {};
  MediaStream? _localStream;
  bool _isMuted = false;
  bool _offlineIceOnly = true;
  Timer? _audioPollTimer;

  final StreamController<double> _audioLevelController = StreamController<double>.broadcast();
  Stream<double> get audioLevels => _audioLevelController.stream;

  RtcMeshEngine({
    required this.localPeerId,
    required this.sendSignal,
    this.onPeerConnectionState,
  });

  bool get isMuted => _isMuted;

  Future<void> startMicrophone({required bool offlineMode}) async {
    _offlineIceOnly = offlineMode;
    if (_localStream != null) return;

    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
      'video': false,
    });

    // Enable hardware speakerphone / Bluetooth routing cleanly
    await Helper.setSpeakerphoneOn(true);

    _audioPollTimer?.cancel();
    _audioPollTimer = Timer.periodic(const Duration(milliseconds: 80), (_) {
      _sampleAudioLevel();
    });
  }

  Future<void> _sampleAudioLevel() async {
    if (_isMuted || _localStream == null) {
      _audioLevelController.add(0);
      return;
    }

    double peak = 0;
    for (final entry in _peers.values) {
      try {
        final stats = await entry.pc.getStats();
        for (final report in stats) {
          if (report.type == 'media-source' && report.values['kind'] == 'audio') {
            final level = (report.values['audioLevel'] as num?)?.toDouble() ?? 0;
            if (level > peak) peak = level;
          }
        }
      } catch (_) {}
    }
    _audioLevelController.add(peak.clamp(0.0, 1.0));
  }

  void setMuted(bool muted) {
    _isMuted = muted;
    final tracks = _localStream?.getAudioTracks() ?? const [];
    for (final track in tracks) {
      track.enabled = !muted;
    }
    if (muted) _audioLevelController.add(0);
  }

  /// Deterministic offer initiation: prevents simultaneous dual-offer glare.
  bool shouldInitiateOffer(String remotePeerId) {
    return localPeerId.compareTo(remotePeerId) < 0;
  }

  Future<void> connectPeer(String remotePeerId) async {
    if (remotePeerId == localPeerId) return;
    await _ensurePeerConnection(remotePeerId);

    if (shouldInitiateOffer(remotePeerId)) {
      await _createAndSendOffer(remotePeerId);
    }
  }

  Future<void> handleIncomingSignal(Map<String, dynamic> msg) async {
    final type = msg['type']?.toString();
    final from = msg['from']?.toString();
    if (from == null || from.isEmpty || from == localPeerId) return;

    switch (type) {
      case 'offer':
        await _handleOffer(from, msg['payload']);
        break;
      case 'answer':
        await _handleAnswer(from, msg['payload']);
        break;
      case 'ice':
        await _handleIce(from, msg['payload']);
        break;
      case 'peer_left':
      case 'leave':
        await removePeer(from);
        break;
    }
  }

  Future<_PeerEntry> _ensurePeerConnection(String remotePeerId) async {
    final existing = _peers[remotePeerId];
    if (existing != null) return existing;

    final config = <String, dynamic>{
      'iceServers': _offlineIceOnly
          ? <Map<String, dynamic>>[]
          : [
              {'urls': 'stun:stun.l.google.com:19302'},
              {'urls': 'stun:stun1.l.google.com:19302'},
            ],
      'sdpSemantics': 'unified-plan',
    };

    final pc = await createPeerConnection(config);
    final entry = _PeerEntry(pc);
    _peers[remotePeerId] = entry;

    if (_localStream != null) {
      for (final track in _localStream!.getAudioTracks()) {
        await pc.addTrack(track, _localStream!);
      }
    }

    pc.onIceCandidate = (candidate) {
      if (candidate.candidate == null) return;
      sendSignal({
        'type': 'ice',
        'from': localPeerId,
        'to': remotePeerId,
        'payload': {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        },
      });
    };

    pc.onConnectionState = (state) {
      onPeerConnectionState?.call(remotePeerId, state);
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        pc.restartIce();
      }
    };

    return entry;
  }

  Future<void> _createAndSendOffer(String remotePeerId) async {
    final entry = await _ensurePeerConnection(remotePeerId);
    final offer = await entry.pc.createOffer({'offerToReceiveAudio': true});
    await entry.pc.setLocalDescription(offer);
    await sendSignal({
      'type': 'offer',
      'from': localPeerId,
      'to': remotePeerId,
      'payload': {'sdp': offer.sdp, 'type': offer.type},
    });
  }

  Future<void> _handleOffer(String remotePeerId, dynamic payload) async {
    if (payload is! Map) return;
    final sdp = payload['sdp']?.toString();
    final type = payload['type']?.toString() ?? 'offer';
    if (sdp == null) return;

    final entry = await _ensurePeerConnection(remotePeerId);
    await entry.pc.setRemoteDescription(RTCSessionDescription(sdp, type));
    entry.remoteDescriptionSet = true;
    await _flushCandidates(entry);

    final answer = await entry.pc.createAnswer();
    await entry.pc.setLocalDescription(answer);
    await sendSignal({
      'type': 'answer',
      'from': localPeerId,
      'to': remotePeerId,
      'payload': {'sdp': answer.sdp, 'type': answer.type},
    });
  }

  Future<void> _handleAnswer(String remotePeerId, dynamic payload) async {
    if (payload is! Map) return;
    final entry = _peers[remotePeerId];
    if (entry == null) return;

    final sdp = payload['sdp']?.toString();
    final type = payload['type']?.toString() ?? 'answer';
    if (sdp == null) return;

    await entry.pc.setRemoteDescription(RTCSessionDescription(sdp, type));
    entry.remoteDescriptionSet = true;
    await _flushCandidates(entry);
  }

  Future<void> _handleIce(String remotePeerId, dynamic payload) async {
    if (payload is! Map) return;
    final entry = await _ensurePeerConnection(remotePeerId);
    final candidate = RTCIceCandidate(
      payload['candidate']?.toString(),
      payload['sdpMid']?.toString(),
      (payload['sdpMLineIndex'] as num?)?.toInt(),
    );
    if (entry.remoteDescriptionSet) {
      await entry.pc.addCandidate(candidate);
    } else {
      entry.pendingCandidates.add(candidate);
    }
  }

  Future<void> _flushCandidates(_PeerEntry entry) async {
    for (final c in entry.pendingCandidates) {
      await entry.pc.addCandidate(c);
    }
    entry.pendingCandidates.clear();
  }

  Future<void> removePeer(String remotePeerId) async {
    final entry = _peers.remove(remotePeerId);
    if (entry != null) {
      await entry.pc.close();
    }
  }

  Future<void> dispose() async {
    _audioPollTimer?.cancel();
    _audioPollTimer = null;

    for (final entry in _peers.values) {
      await entry.pc.close();
    }
    _peers.clear();

    if (_localStream != null) {
      for (final track in _localStream!.getTracks()) {
        await track.stop();
      }
      await _localStream!.dispose();
      _localStream = null;
    }

    await _audioLevelController.close();
  }
}
