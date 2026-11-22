import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/models/bubble_group.dart';
import '../../core/storage/bubble_store.dart';
import '../../core/theme/bubble_theme.dart';
import '../../core/transport/transport_orchestrator.dart';
import '../bubble_visuals/bubble_painter.dart';
import '../common/glass_surface.dart';
import '../qr/qr_scanner_screen.dart';
import '../room/room_screen.dart';

class HomeScreen extends StatefulWidget {
  final BubbleStore store;
  final TransportOrchestrator orchestrator;

  const HomeScreen({
    super.key,
    required this.store,
    required this.orchestrator,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  StreamSubscription<Uri>? _linkSub;

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onChanged);
    widget.orchestrator.addListener(_onChanged);
    widget.orchestrator.startNearbyDiscovery(
      displayName: widget.store.nickname.isNotEmpty ? widget.store.nickname : 'Bubble',
    );
    _initDeepLinks();
  }

  Future<void> _initDeepLinks() async {
    try {
      final appLinks = AppLinks();
      final initial = await appLinks.getInitialLink();
      if (initial != null) {
        await _handleIncomingUri(initial);
      }
      _linkSub = appLinks.uriLinkStream.listen(_handleIncomingUri);
    } catch (_) {
      // Ignore in test/unsupported environments
    }
  }

  Future<void> _handleIncomingUri(Uri uri) async {
    final parsed = BubbleGroup.parseQrOrLink(uri.toString());
    if (parsed == null) return;
    final group = await widget.store.joinFromInvite(parsed);
    if (!mounted) return;
    _openRoom(group, directWsUrl: parsed.localWsUrl);
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    widget.store.removeListener(_onChanged);
    widget.orchestrator.removeListener(_onChanged);
    widget.orchestrator.stopNearbyDiscovery();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _openRoom(BubbleGroup group, {String? directWsUrl}) {
    HapticFeedback.selectionClick();
    Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (_) => RoomScreen(
          group: group,
          store: widget.store,
          orchestrator: widget.orchestrator,
          directLocalWsUrl: directWsUrl,
        ),
      ),
    );
  }

  void _showCreateSheet() {
    final s = AppStrings(widget.store.language);
    final nameCtrl = TextEditingController();

    showAppleGlassSheet(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              s.createBubble,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 14),
            CupertinoTextField(
              controller: nameCtrl,
              autofocus: true,
              placeholder: s.groupNameHint,
              placeholderStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
              style: const TextStyle(color: Colors.white),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            const SizedBox(height: 16),
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () async {
                final group = await widget.store.createGroup(customName: nameCtrl.text);
                if (!ctx.mounted) return;
                Navigator.of(ctx).pop();
                _openRoom(group);
              },
              child: Container(
                height: 50,
                decoration: BoxDecoration(
                  gradient: BubbleTheme.primaryGradient,
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Text(
                  s.createBubble,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openQrScanner() async {
    HapticFeedback.selectionClick();
    final payload = await Navigator.of(context).push<BubbleInvitePayload>(
      CupertinoPageRoute(
        fullscreenDialog: true,
        builder: (_) => const QrScannerScreen(),
      ),
    );
    if (payload == null) return;
    final group = await widget.store.joinFromInvite(payload);
    if (!mounted) return;
    _openRoom(group, directWsUrl: payload.localWsUrl);
  }

  void _showJoinSheet() {
    final s = AppStrings(widget.store.language);
    final inputCtrl = TextEditingController();

    showAppleGlassSheet(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              s.joinBubble,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 14),
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () {
                Navigator.of(ctx).pop();
                _openQrScanner();
              },
              child: Container(
                height: 52,
                decoration: BoxDecoration(
                  gradient: BubbleTheme.primaryGradient,
                  borderRadius: BorderRadius.circular(16),
                ),
                alignment: Alignment.center,
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(CupertinoIcons.qrcode_viewfinder, size: 20, color: Colors.white),
                    SizedBox(width: 8),
                    Text(
                      'Scansiona QR con Fotocamera',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Oppure inserisci codice a 6 cifre / link WhatsApp',
              style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.58)),
            ),
            const SizedBox(height: 8),
            CupertinoTextField(
              controller: inputCtrl,
              placeholder: '123456 o https://.../join/...',
              placeholderStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
              style: const TextStyle(color: Colors.white),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            const SizedBox(height: 12),
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () async {
                final parsed = BubbleGroup.parseQrOrLink(inputCtrl.text);
                if (parsed == null) return;
                final group = await widget.store.joinFromInvite(parsed);
                if (!ctx.mounted) return;
                Navigator.of(ctx).pop();
                _openRoom(group, directWsUrl: parsed.localWsUrl);
              },
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
                ),
                alignment: Alignment.center,
                child: const Text(
                  'Entra con Codice / Link',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showGroupsSheet() {
    final s = AppStrings(widget.store.language);

    showAppleGlassSheet(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              s.yourBubbles,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            if (widget.store.groups.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 28),
                child: Text(
                  s.noSavedBubbles,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: widget.store.groups.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, idx) {
                    final g = widget.store.groups[idx];
                    return GlassSurface(
                      borderRadius: 18,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                Navigator.of(ctx).pop();
                                _openRoom(g);
                              },
                              behavior: HitTestBehavior.opaque,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    g.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '#${g.code}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.white.withValues(alpha: 0.55),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: s.abandonGroupBtn,
                            icon: const Icon(CupertinoIcons.trash, size: 18, color: BubbleTheme.dangerRed),
                            onPressed: () => widget.store.abandonGroup(g.code),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showSettingsSheet() {
    final s = AppStrings(widget.store.language);
    final nickCtrl = TextEditingController(text: widget.store.nickname);
    final serverCtrl = TextEditingController(text: widget.store.serverUrl);

    showAppleGlassSheet(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 16, 22, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(s.settings, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            Text(s.profile, style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.55))),
            const SizedBox(height: 6),
            CupertinoTextField(
              controller: nickCtrl,
              style: const TextStyle(color: Colors.white),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            const SizedBox(height: 14),
            Text(s.serverUrlLabel, style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.55))),
            const SizedBox(height: 6),
            CupertinoTextField(
              controller: serverCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(s.language, style: const TextStyle(fontSize: 14)),
                CupertinoSegmentedControl<String>(
                  groupValue: widget.store.language,
                  children: const {
                    'it': Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('IT')),
                    'en': Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('EN')),
                  },
                  onValueChanged: (val) => widget.store.setLanguage(val),
                ),
              ],
            ),
            const SizedBox(height: 18),
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () async {
                if (nickCtrl.text.trim().isNotEmpty) {
                  await widget.store.setNickname(nickCtrl.text);
                }
                await widget.store.setServerUrl(serverCtrl.text);
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  gradient: BubbleTheme.primaryGradient,
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Text(s.saveBtn, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings(widget.store.language);
    final initial = widget.store.nickname.isNotEmpty
        ? widget.store.nickname[0].toUpperCase()
        : 'B';
    final nearby = widget.orchestrator.nearbyBubbles;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: BubbleTheme.backgroundGradient),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Column(
              children: [
                // Apple-clean Top Navigation Bar
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    GestureDetector(
                      onTap: _showSettingsSheet,
                      child: Container(
                        width: 42,
                        height: 42,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: BubbleTheme.primaryGradient,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          initial,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: _showGroupsSheet,
                      child: GlassSurface(
                        borderRadius: 99,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(CupertinoIcons.bubble_left_bubble_right, size: 16),
                            const SizedBox(width: 6),
                            Text(
                              '${widget.store.groups.length}',
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

                // Nearby Offline Bubbles Capsule (Apple Multipeer / LAN)
                if (nearby.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 40,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: nearby.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (_, idx) {
                        final item = nearby[idx];
                        return GestureDetector(
                          onTap: () async {
                            final grp = await widget.store.joinFromInvite(
                              BubbleInvitePayload(
                                groupId: 'grp_${item.roomCode}',
                                code: item.roomCode,
                                secret: item.roomCode,
                                name: item.roomName,
                                localWsUrl: item.wsUrl,
                              ),
                            );
                            _openRoom(grp, directWsUrl: item.wsUrl);
                          },
                          child: GlassSurface(
                            borderRadius: 99,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(CupertinoIcons.dot_radiowaves_left_right,
                                    size: 14, color: BubbleTheme.liveEmerald),
                                const SizedBox(width: 6),
                                Text(item.roomName, style: const TextStyle(fontSize: 13)),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],

                // Center Hero Bubble
                const Expanded(
                  child: Center(
                    child: InteractiveBubble(audioLevel: 0.10, size: 240),
                  ),
                ),

                // Bottom Apple-style Action Dock
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: _showCreateSheet,
                        child: GlassSurface(
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          tint: BubbleTheme.primaryViolet.withValues(alpha: 0.22),
                          borderColor: BubbleTheme.primaryViolet.withValues(alpha: 0.45),
                          child: Column(
                            children: [
                              const Icon(CupertinoIcons.plus_circle_fill, size: 24),
                              const SizedBox(height: 8),
                              Text(s.createBubble,
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GestureDetector(
                        onTap: _showJoinSheet,
                        child: GlassSurface(
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          child: Column(
                            children: [
                              const Icon(CupertinoIcons.qrcode_viewfinder, size: 24),
                              const SizedBox(height: 8),
                              Text(s.joinBubble,
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
