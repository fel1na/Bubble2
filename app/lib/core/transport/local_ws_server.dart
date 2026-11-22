import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Native Dart WebSocket signaling server running directly on the Host phone.
/// Replaces the broken Capacitor WebSocket plugin from Bubble v1.
class LocalWsServer {
  HttpServer? _httpServer;
  final Map<String, WebSocket> _clients = {};
  final StreamController<Map<String, dynamic>> _inbound =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get messages => _inbound.stream;
  bool get isRunning => _httpServer != null;
  int get port => _httpServer?.port ?? 8787;

  Future<int> start({int preferredPort = 8787}) async {
    if (_httpServer != null) return _httpServer!.port;

    try {
      _httpServer = await HttpServer.bind(InternetAddress.anyIPv4, preferredPort);
    } catch (_) {
      _httpServer = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    }

    _httpServer!.listen((HttpRequest req) async {
      if (req.uri.path == '/health') {
        req.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'ok': true, 'clients': _clients.length}));
        await req.response.close();
        return;
      }

      if (WebSocketTransformer.isUpgradeRequest(req)) {
        final ws = await WebSocketTransformer.upgrade(req);
        _attachClient(ws);
      } else {
        req.response.statusCode = HttpStatus.notFound;
        await req.response.close();
      }
    });

    return _httpServer!.port;
  }

  void _attachClient(WebSocket ws) {
    String? boundPeerId;

    ws.listen(
      (raw) {
        try {
          final msg = jsonDecode(raw.toString()) as Map<String, dynamic>;
          final from = msg['from']?.toString();
          if (msg['type'] == 'join' && from != null && from.isNotEmpty) {
            boundPeerId = from;
            _clients[from] = ws;
          }
          _inbound.add(msg);
        } catch (_) {}
      },
      onDone: () {
        if (boundPeerId != null) {
          _clients.remove(boundPeerId);
          _inbound.add({'type': 'peer_left', 'peerId': boundPeerId});
        }
      },
      onError: (_) {
        if (boundPeerId != null) {
          _clients.remove(boundPeerId);
          _inbound.add({'type': 'peer_left', 'peerId': boundPeerId});
        }
      },
    );
  }

  void sendToPeer(String peerId, Map<String, dynamic> payload) {
    final ws = _clients[peerId];
    if (ws != null && ws.readyState == WebSocket.open) {
      ws.add(jsonEncode(payload));
    }
  }

  void broadcast(Map<String, dynamic> payload, {String? exceptPeerId}) {
    final encoded = jsonEncode(payload);
    for (final entry in _clients.entries) {
      if (entry.key == exceptPeerId) continue;
      if (entry.value.readyState == WebSocket.open) {
        entry.value.add(encoded);
      }
    }
  }

  Future<void> stop() async {
    for (final ws in _clients.values) {
      await ws.close().catchError((_) {});
    }
    _clients.clear();
    await _httpServer?.close(force: true);
    _httpServer = null;
  }

  /// Resolves the device's real local IPv4 address (never hardcodes 192.168.43.1).
  static Future<String?> resolveLocalIpv4() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) return addr.address;
        }
      }
    } catch (_) {}
    return null;
  }
}
