import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/models/bubble_group.dart';
import '../../core/models/peer_participant.dart';
import '../../core/theme/bubble_theme.dart';
import '../common/glass_surface.dart';

/// 6-digit glass code tiles inspired by the original Bubble RoomCodeDisplay.
class RoomCodeTiles extends StatelessWidget {
  final String code;
  final double tileHeight;

  const RoomCodeTiles({
    super.key,
    required this.code,
    this.tileHeight = 46,
  });

  @override
  Widget build(BuildContext context) {
    final digits = code.padRight(6).substring(0, 6).split('');
    return Row(
      children: [
        for (int i = 0; i < digits.length; i++) ...[
          if (i > 0) const SizedBox(width: 7),
          Expanded(
            child: Container(
              height: tileHeight,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              ),
              alignment: Alignment.center,
              child: Text(
                digits[i],
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Compact frosted room sharing card with 6-digit tiles + Copy / WhatsApp Share / QR modal.
class RoomShareCard extends StatefulWidget {
  final BubbleGroup group;
  final String serverUrl;
  final String myName;
  final List<PeerParticipant> participants;
  final String? localWsUrl;
  final String? wifiSsid;
  final String? wifiPassword;
  final AppStrings strings;

  const RoomShareCard({
    super.key,
    required this.group,
    required this.serverUrl,
    required this.myName,
    required this.participants,
    required this.strings,
    this.localWsUrl,
    this.wifiSsid,
    this.wifiPassword,
  });

  @override
  State<RoomShareCard> createState() => _RoomShareCardState();
}

class _RoomShareCardState extends State<RoomShareCard> {
  bool _copied = false;

  Future<void> _copyCode() async {
    await Clipboard.setData(ClipboardData(text: widget.group.code));
    HapticFeedback.lightImpact();
    if (!mounted) return;
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  Future<void> _shareWhatsApp() async {
    HapticFeedback.selectionClick();
    final inviteUrl = widget.group.toInviteUrl(widget.serverUrl);
    await Share.share(
      'Entra nella mia Bubble "${widget.group.name}" (#${widget.group.code}):\n$inviteUrl',
    );
  }

  void _openQrModal() {
    HapticFeedback.selectionClick();
    final qrPayload = widget.group.toQrPayload(
      localWsUrl: widget.localWsUrl,
      wifiSsid: widget.wifiSsid,
      wifiPassword: widget.wifiPassword,
    );

    showAppleGlassSheet(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.group.name,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                GestureDetector(
                  onTap: () => Navigator.of(ctx).pop(),
                  child: const GlassSurface(
                    borderRadius: 99,
                    padding: EdgeInsets.all(8),
                    child: Icon(CupertinoIcons.xmark, size: 14),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
              child: QrImageView(
                data: qrPayload,
                size: 196,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 18),
            RoomCodeTiles(code: widget.group.code, tileHeight: 42),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: _shareWhatsApp,
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: BubbleTheme.primaryGradient,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(CupertinoIcons.share, size: 17, color: Colors.white),
                      const SizedBox(width: 8),
                      Text(
                        widget.strings.inviteWhatsapp,
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

  void _openParticipantsSheet() {
    HapticFeedback.selectionClick();
    showAppleGlassSheet(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Nel Bubble',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            _ParticipantTile(name: widget.myName, isSelf: true, isMuted: false),
            for (final p in widget.participants) ...[
              const SizedBox(height: 8),
              _ParticipantTile(name: p.displayName, isSelf: false, isMuted: p.isMuted),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalCount = widget.participants.length + 1;

    return GlassSurface(
      borderRadius: 24,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                widget.group.name,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              GestureDetector(
                onTap: _openParticipantsSheet,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(CupertinoIcons.person_2_fill, size: 14, color: Colors.white70),
                    const SizedBox(width: 5),
                    Text('$totalCount', style: const TextStyle(fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          RoomCodeTiles(code: widget.group.code),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _ActionPill(
                  icon: _copied ? CupertinoIcons.check_mark : CupertinoIcons.doc_on_doc,
                  label: _copied ? 'Copiato' : 'Copia',
                  iconColor: _copied ? BubbleTheme.liveEmerald : Colors.white70,
                  onTap: _copyCode,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ActionPill(
                  icon: CupertinoIcons.share,
                  label: 'WhatsApp',
                  iconColor: Colors.white70,
                  onTap: _shareWhatsApp,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ActionPill(
                  icon: CupertinoIcons.qrcode,
                  label: 'QR',
                  iconColor: BubbleTheme.accentMagenta,
                  onTap: _openQrModal,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color iconColor;
  final VoidCallback onTap;

  const _ActionPill({
    required this.icon,
    required this.label,
    required this.iconColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 38,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: iconColor),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

class _ParticipantTile extends StatelessWidget {
  final String name;
  final bool isSelf;
  final bool isMuted;

  const _ParticipantTile({
    required this.name,
    required this.isSelf,
    required this.isMuted,
  });

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: isSelf ? BubbleTheme.primaryGradient : null,
              color: isSelf ? null : BubbleTheme.primaryViolet.withValues(alpha: 0.28),
            ),
            alignment: Alignment.center,
            child: Text(initial, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(name, style: const TextStyle(fontSize: 14))),
          if (isSelf)
            Text('tu', style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.5)))
          else
            Icon(
              isMuted ? CupertinoIcons.mic_off : CupertinoIcons.mic_fill,
              size: 14,
              color: isMuted ? Colors.white38 : BubbleTheme.liveEmerald,
            ),
        ],
      ),
    );
  }
}
