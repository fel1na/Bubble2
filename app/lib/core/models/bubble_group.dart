import 'dart:convert';
import 'dart:math';

/// Persistent WhatsApp-style Bubble group stored locally on the user's device.
/// Membership persists across voice sessions until the user explicitly abandons the group.
class BubbleGroup {
  final String id;
  final String code;
  final String secret;
  final String name;
  final bool isCreator;
  final DateTime joinedAt;
  final DateTime lastSessionAt;
  final bool muted;

  const BubbleGroup({
    required this.id,
    required this.code,
    required this.secret,
    required this.name,
    required this.isCreator,
    required this.joinedAt,
    required this.lastSessionAt,
    this.muted = false,
  });

  BubbleGroup copyWith({
    String? name,
    DateTime? lastSessionAt,
    bool? muted,
  }) {
    return BubbleGroup(
      id: id,
      code: code,
      secret: secret,
      name: name ?? this.name,
      isCreator: isCreator,
      joinedAt: joinedAt,
      lastSessionAt: lastSessionAt ?? this.lastSessionAt,
      muted: muted ?? this.muted,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'code': code,
        'secret': secret,
        'name': name,
        'isCreator': isCreator,
        'joinedAt': joinedAt.toIso8601String(),
        'lastSessionAt': lastSessionAt.toIso8601String(),
        'muted': muted,
      };

  factory BubbleGroup.fromJson(Map<String, dynamic> json) {
    return BubbleGroup(
      id: json['id'] as String,
      code: json['code'] as String,
      secret: json['secret'] as String,
      name: json['name'] as String,
      isCreator: json['isCreator'] as bool? ?? false,
      joinedAt: DateTime.tryParse(json['joinedAt'] as String? ?? '') ?? DateTime.now(),
      lastSessionAt: DateTime.tryParse(json['lastSessionAt'] as String? ?? '') ?? DateTime.now(),
      muted: json['muted'] as bool? ?? false,
    );
  }

  /// Generates a compact QR payload containing group identity + optional local endpoint.
  String toQrPayload({String? localWsUrl, String? wifiSsid, String? wifiPassword}) {
    return jsonEncode({
      'v': 2,
      'type': 'bubble2',
      'id': id,
      'code': code,
      'secret': secret,
      'name': name,
      'ws': ?localWsUrl,
      'ssid': ?wifiSsid,
      'pass': ?wifiPassword,
    });
  }

  /// Builds an invite link shareable on WhatsApp.
  /// The secret stays in the URL fragment (#k=) so the server never needs to store it.
  String toInviteUrl(String serverBaseHttpUrl) {
    final cleanBase = serverBaseHttpUrl.endsWith('/')
        ? serverBaseHttpUrl.substring(0, serverBaseHttpUrl.length - 1)
        : serverBaseHttpUrl;
    final encodedName = Uri.encodeQueryComponent(name);
    return '$cleanBase/join/$code?name=$encodedName#k=$secret';
  }

  static String generateSixDigitCode([Random? random]) {
    final rng = random ?? Random.secure();
    return (100000 + rng.nextInt(900000)).toString();
  }

  static String generateSecret([Random? random]) {
    final rng = random ?? Random.secure();
    final bytes = List<int>.generate(24, (_) => rng.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  static BubbleInvitePayload? parseQrOrLink(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    // 1. JSON QR payload
    if (trimmed.startsWith('{')) {
      try {
        final map = jsonDecode(trimmed) as Map<String, dynamic>;
        final code = (map['code'] ?? map['room']?['code'])?.toString();
        if (code == null || code.length != 6) return null;
        return BubbleInvitePayload(
          groupId: map['id']?.toString() ?? 'grp_$code',
          code: code,
          secret: map['secret']?.toString() ?? code,
          name: (map['name'] ?? map['room']?['name'] ?? 'Bubble #$code').toString(),
          localWsUrl: map['ws']?.toString() ?? map['server']?.toString(),
          wifiSsid: map['ssid']?.toString(),
          wifiPassword: map['pass']?.toString(),
        );
      } catch (_) {
        return null;
      }
    }

    // 2. WhatsApp HTTPS link or bubble:// deep link
    final uri = Uri.tryParse(trimmed);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https' || uri.scheme == 'bubble')) {
      String? code = uri.queryParameters['code'];
      if (code == null && uri.pathSegments.length >= 2 && uri.pathSegments.first == 'join') {
        code = uri.pathSegments[1];
      }
      final cleanCode = code?.replaceAll(RegExp(r'\D'), '');
      if (cleanCode != null && cleanCode.length == 6) {
        String secret = cleanCode;
        if (uri.fragment.startsWith('k=')) {
          secret = uri.fragment.substring(2);
        }
        return BubbleInvitePayload(
          groupId: 'grp_$cleanCode',
          code: cleanCode,
          secret: secret,
          name: uri.queryParameters['name'] ?? 'Bubble #$cleanCode',
        );
      }
    }

    // 3. Raw 6-digit code
    final digits = trimmed.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 6) {
      return BubbleInvitePayload(
        groupId: 'grp_$digits',
        code: digits,
        secret: digits,
        name: 'Bubble #$digits',
      );
    }

    return null;
  }
}

class BubbleInvitePayload {
  final String groupId;
  final String code;
  final String secret;
  final String name;
  final String? localWsUrl;
  final String? wifiSsid;
  final String? wifiPassword;

  const BubbleInvitePayload({
    required this.groupId,
    required this.code,
    required this.secret,
    required this.name,
    this.localWsUrl,
    this.wifiSsid,
    this.wifiPassword,
  });
}
