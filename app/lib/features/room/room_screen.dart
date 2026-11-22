import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/models/bubble_group.dart';
import '../../core/models/peer_participant.dart';
import '../../core/storage/bubble_store.dart';
import '../../core/theme/bubble_theme.dart';
import '../../core/transport/transport_orchestrator.dart';
import '../bubble_visuals/bubble_painter.dart';
import '../common/glass_surface.dart';
import 'room_share_widgets.dart';

class RoomScreen extends StatefulWidget {
  final BubbleGroup group;
  final BubbleStore store;
  final TransportOrchestrator orchestrator;
  final String? directLocalWsUrl;

  const RoomScreen({
    super.key,
    required this.group,
    required this.store,
    required this.orchestrator,
    this.directLocalWsUrl,
  });

  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen> {
  late BubbleGroup _group;
  bool _bursting = false;
  double _musicVolume = 0.35;

  @override
  void initState() {
    super.initState();
    _group = widget.group;
    widget.orchestrator.addListener(_onChanged);
    widget.store.markSessionVisited(_group.code);
  }

  @override
  void dispose() {
    widget.orchestrator.removeListener(_onChanged);
    widget.orchestrator.stopSession();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _connectVoice() async {
    HapticFeedback.mediumImpact();
    await widget.orchestrator.startSession(
      group: _group,
      localPeerId: widget.store.deviceId,
      displayName: widget.store.nickname.isNotEmpty ? widget.store.nickname : 'Guest',
      internetWsUrl: widget.store.wsServerUrl,
      directLocalWsUrl: widget.directLocalWsUrl,
    );
  }

  Future<void> _forceOnlineFallback() async {
    HapticFeedback.selectionClick();
    await widget.orchestrator.connectInternetFallback(
      group: _group,
      localPeerId: widget.store.deviceId,
      displayName: widget.store.nickname.isNotEmpty ? widget.store.nickname : 'Guest',
      internetWsUrl: widget.store.wsServerUrl,
    );
  }

  void _showQrAndInviteSheet() {
    final s = AppStrings(widget.store.language);
    final qrPayload = _group.toQrPayload(
      localWsUrl: widget.orchestrator.localQrEndpointUrl,
      wifiSsid: widget.orchestrator.hotspotSsid,
      wifiPassword: widget.orchestrator.hotspotPassword,
    );
    final inviteUrl = _group.toInviteUrl(widget.store.serverUrl);

    showAppleGlassSheet(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 16, 22, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _group.name,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              '#${_group.code}',
              style: TextStyle(
                fontSize: 14,
                letterSpacing: 3,
                color: Colors.white.withValues(alpha: 0.65),
              ),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
              ),
              child: QrImageView(
                data: qrPayload,
                size: 190,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () {
                  Share.share(
                    'Entra nella mia Bubble "${_group.name}" (#${_group.code}): $inviteUrl',
                  );
                },
                child: Container(
                  height: 50,
                  decoration: BoxDecoration(
                    gradient: BubbleTheme.primaryGradient,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(CupertinoIcons.share, size: 18, color: Colors.white),
                      const SizedBox(width: 8),
                      Text(
                        s.inviteWhatsapp,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showMusicSheet() {
    showAppleGlassSheet(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (_, setModalState) => Padding(
          padding: const EdgeInsets.fromLTRB(22, 16, 22, 26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Musica di sottofondo (locale)',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text(
                'La musica resta nelle tue cuffie mentre parli nella Bubble.',
                style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.6)),
              ),
              const SizedBox(height: 16),
              CupertinoSlider(
                value: _musicVolume,
                activeColor: BubbleTheme.primaryViolet,
                onChanged: (v) {
                  setModalState(() => _musicVolume = v);
                  setState(() => _musicVolume = v);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmLeave() {
    final s = AppStrings(widget.store.language);
    showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(s.leaveSessionTitle),
        message: Text(s.leaveSessionSub),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(ctx).pop();
              setState(() => _bursting = true);
            },
            child: Text(s.leaveSessionBtn),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () async {
              Navigator.of(ctx).pop();
              await widget.store.abandonGroup(_group.code);
              if (mounted) setState(() => _bursting = true);
            },
            child: Text(s.abandonGroupBtn),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(s.stayBtn),
        ),
      ),
    );
  }

  String _statusLabel(AppStrings s) {
    switch (widget.orchestrator.mode) {
      case TransportMode.offlineMultipeer:
        return s.statusOfflineMultipeer;
      case TransportMode.offlineLan:
        return s.statusOfflineLan;
      case TransportMode.offlineHotspot:
        return s.statusOfflineHotspot;
      case TransportMode.onlineServer:
        return s.statusOnline;
      case TransportMode.connecting:
        return s.statusConnecting;
      case TransportMode.idle:
        return s.statusReady;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings(widget.store.language);
    final orch = widget.orchestrator;
    final isLive = orch.isLive;
    final participants = orch.participants;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: BubbleTheme.backgroundGradient),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Column(
              children: [
                // Status & Invite Top Row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    GestureDetector(
                      onTap: isLive ? _forceOnlineFallback : null,
                      child: GlassSurface(
                        borderRadius: 99,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isLive
                                    ? BubbleTheme.liveEmerald
                                    : Colors.white.withValues(alpha: 0.4),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _statusLabel(s),
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: _showQrAndInviteSheet,
                      child: GlassSurface(
                        borderRadius: 99,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(CupertinoIcons.qrcode, size: 15),
                            const SizedBox(width: 6),
                            Text(s.showQr, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

                const Spacer(),

                // Main Bubble
                if (_bursting)
                  BubbleBurstView(
                    size: 230,
                    onComplete: () async {
                      final nav = Navigator.of(context);
                      await orch.stopSession();
                      if (mounted) nav.pop();
                    },
                  )
                else
                  InteractiveBubble(
                    size: 230,
                    audioLevel: orch.localAudioLevel,
                    isLive: isLive,
                    isMuted: orch.isMuted,
                    onTap: !isLive && orch.mode != TransportMode.connecting
                        ? _connectVoice
                        : null,
                  ),

                const SizedBox(height: 10),
                Text(
                  _group.name,
                  style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 4),
                Text(
                  isLive
                      ? (orch.isMuted ? s.muted : '${participants.length + 1} · ${s.liveVoice}')
                      : s.tapToJoinVoice,
                  style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.6)),
                ),

                if (participants.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: participants
                        .map(
                          (p) => GlassSurface(
                            borderRadius: 99,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  p.isMuted ? CupertinoIcons.mic_off : CupertinoIcons.mic_fill,
                                  size: 12,
                                  color: p.isMuted
                                      ? Colors.white.withValues(alpha: 0.45)
                                      : BubbleTheme.liveEmerald,
                                ),
                                const SizedBox(width: 6),
                                Text(p.displayName, style: const TextStyle(fontSize: 12)),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],

                const Spacer(),

                if (!_bursting) ...[
                  RoomShareCard(
                    group: _group,
                    serverUrl: widget.store.serverUrl,
                    myName: widget.store.nickname.isNotEmpty ? widget.store.nickname : 'Tu',
                    participants: participants,
                    localWsUrl: orch.localQrEndpointUrl,
                    wifiSsid: orch.hotspotSsid,
                    wifiPassword: orch.hotspotPassword,
                    strings: s,
                  ),
                  const SizedBox(height: 18),
                ],

                // Bottom Controls
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    GestureDetector(
                      onTap: _showMusicSheet,
                      child: const GlassSurface(
                        borderRadius: 99,
                        padding: EdgeInsets.all(18),
                        child: Icon(CupertinoIcons.music_note_2, size: 22),
                      ),
                    ),
                    GestureDetector(
                      onTap: isLive ? orch.toggleMute : _connectVoice,
                      child: GlassSurface(
                        borderRadius: 99,
                        padding: const EdgeInsets.all(20),
                        borderColor: isLive && !orch.isMuted
                            ? BubbleTheme.liveEmerald.withValues(alpha: 0.75)
                            : BubbleTheme.glassBorder,
                        child: Icon(
                          orch.isMuted ? CupertinoIcons.mic_off : CupertinoIcons.mic_fill,
                          size: 24,
                          color: isLive && !orch.isMuted ? BubbleTheme.liveEmerald : Colors.white,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: _confirmLeave,
                      child: GlassSurface(
                        borderRadius: 99,
                        padding: const EdgeInsets.all(18),
                        borderColor: BubbleTheme.dangerRed.withValues(alpha: 0.55),
                        child: const Icon(CupertinoIcons.xmark, size: 22, color: BubbleTheme.dangerRed),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
