import 'package:bubble/core/models/bubble_group.dart';
import 'package:bubble/core/storage/bubble_store.dart';
import 'package:bubble/core/transport/rtc_mesh_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BubbleGroup invite & QR parsing', () {
    test('parses QR payload with local Wi-Fi and WebSocket endpoint', () {
      final group = BubbleGroup(
        id: 'grp_1',
        code: '482910',
        secret: 'secret_abc',
        name: 'Montagna',
        isCreator: true,
        joinedAt: DateTime(2026),
        lastSessionAt: DateTime(2026),
      );

      final qr = group.toQrPayload(
        localWsUrl: 'ws://192.168.49.1:8787',
        wifiSsid: 'Bubble_AP',
        wifiPassword: 'pass123',
      );

      final parsed = BubbleGroup.parseQrOrLink(qr);
      expect(parsed, isNotNull);
      expect(parsed!.code, '482910');
      expect(parsed.secret, 'secret_abc');
      expect(parsed.name, 'Montagna');
      expect(parsed.localWsUrl, 'ws://192.168.49.1:8787');
      expect(parsed.wifiSsid, 'Bubble_AP');
      expect(parsed.wifiPassword, 'pass123');
    });

    test('parses WhatsApp HTTPS invite link keeping secret in fragment', () {
      final group = BubbleGroup(
        id: 'grp_2',
        code: '918273',
        secret: 'topSecretKey',
        name: 'Ristorante Crew',
        isCreator: true,
        joinedAt: DateTime(2026),
        lastSessionAt: DateTime(2026),
      );

      final url = group.toInviteUrl('https://bubble.example.org');
      expect(url, contains('#k=topSecretKey'));

      final parsed = BubbleGroup.parseQrOrLink(url);
      expect(parsed, isNotNull);
      expect(parsed!.code, '918273');
      expect(parsed.secret, 'topSecretKey');
      expect(parsed.name, 'Ristorante Crew');
    });
  });

  group('BubbleStore persistent groups', () {
    test('creates, keeps, and explicitly abandons persistent groups', () async {
      SharedPreferences.setMockInitialValues({});
      final store = BubbleStore();
      await store.load();
      await store.setNickname('Ale');

      final group = await store.createGroup(customName: 'Weekend');
      expect(store.groups.length, 1);
      expect(store.groups.first.name, 'Weekend');

      await store.abandonGroup(group.code);
      expect(store.groups, isEmpty);
    });
  });

  group('RtcMeshEngine glare prevention', () {
    test('exactly one peer initiates WebRTC offer for any pair', () {
      final a = RtcMeshEngine(localPeerId: 'dev_aaa', sendSignal: (_) async {});
      final b = RtcMeshEngine(localPeerId: 'dev_bbb', sendSignal: (_) async {});

      expect(a.shouldInitiateOffer('dev_bbb'), isTrue);
      expect(b.shouldInitiateOffer('dev_aaa'), isFalse);
    });
  });
}
