enum TransportMode {
  idle,
  connecting,
  offlineMultipeer,
  offlineLan,
  offlineHotspot,
  onlineServer,
}

class PeerParticipant {
  final String peerId;
  final String displayName;
  final bool isMuted;
  final double audioLevel;

  const PeerParticipant({
    required this.peerId,
    required this.displayName,
    this.isMuted = false,
    this.audioLevel = 0,
  });

  PeerParticipant copyWith({
    String? displayName,
    bool? isMuted,
    double? audioLevel,
  }) {
    return PeerParticipant(
      peerId: peerId,
      displayName: displayName ?? this.displayName,
      isMuted: isMuted ?? this.isMuted,
      audioLevel: audioLevel ?? this.audioLevel,
    );
  }
}

class NearbyBubbleDiscovery {
  final String roomCode;
  final String roomName;
  final String hostName;
  final String source; // 'multipeer' | 'lan' | 'ble'
  final String? wsUrl;

  const NearbyBubbleDiscovery({
    required this.roomCode,
    required this.roomName,
    required this.hostName,
    required this.source,
    this.wsUrl,
  });
}
