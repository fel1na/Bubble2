import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/bubble_group.dart';

class BubbleStore extends ChangeNotifier {
  static const _kDeviceIdKey = 'bubble2_device_id';
  static const _kNicknameKey = 'bubble2_nickname';
  static const _kLanguageKey = 'bubble2_lang';
  static const _kGroupsKey = 'bubble2_groups';
  static const _kServerUrlKey = 'bubble2_server_url';

  static const String defaultServerUrl = 'http://localhost:8787';

  final Uuid _uuid = const Uuid();
  SharedPreferences? _prefs;

  String _deviceId = '';
  String _nickname = '';
  String _language = 'it';
  String _serverUrl = defaultServerUrl;
  List<BubbleGroup> _groups = [];
  bool _loaded = false;

  bool get isLoaded => _loaded;
  String get deviceId => _deviceId;
  String get nickname => _nickname;
  bool get hasProfile => _nickname.trim().isNotEmpty;
  String get language => _language;
  String get serverUrl => _serverUrl;
  List<BubbleGroup> get groups => List.unmodifiable(_groups);

  String get wsServerUrl {
    final uri = Uri.tryParse(_serverUrl);
    if (uri == null || uri.host.isEmpty) return 'ws://localhost:8787/ws';
    final wsScheme = uri.scheme == 'https' ? 'wss' : 'ws';
    final portPart = uri.hasPort ? ':${uri.port}' : '';
    return '$wsScheme://${uri.host}$portPart/ws';
  }

  Future<void> load() async {
    _prefs ??= await SharedPreferences.getInstance();

    _deviceId = _prefs!.getString(_kDeviceIdKey) ?? '';
    if (_deviceId.isEmpty) {
      _deviceId = 'dev_${_uuid.v4().substring(0, 12)}';
      await _prefs!.setString(_kDeviceIdKey, _deviceId);
    }

    _nickname = _prefs!.getString(_kNicknameKey) ?? '';
    _language = _prefs!.getString(_kLanguageKey) ?? 'it';
    _serverUrl = _prefs!.getString(_kServerUrlKey) ?? defaultServerUrl;

    final rawGroups = _prefs!.getString(_kGroupsKey);
    if (rawGroups != null && rawGroups.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawGroups) as List<dynamic>;
        _groups = decoded
            .map((item) => BubbleGroup.fromJson(item as Map<String, dynamic>))
            .toList()
          ..sort((a, b) => b.lastSessionAt.compareTo(a.lastSessionAt));
      } catch (_) {
        _groups = [];
      }
    }

    _loaded = true;
    notifyListeners();
  }

  Future<void> setNickname(String name) async {
    _nickname = name.trim();
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_kNicknameKey, _nickname);
    notifyListeners();
  }

  Future<void> setLanguage(String lang) async {
    _language = lang == 'en' ? 'en' : 'it';
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_kLanguageKey, _language);
    notifyListeners();
  }

  Future<void> setServerUrl(String url) async {
    final cleaned = url.trim();
    if (cleaned.isEmpty) return;
    _serverUrl = cleaned;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_kServerUrlKey, _serverUrl);
    notifyListeners();
  }

  Future<BubbleGroup> createGroup({String? customName}) async {
    final code = BubbleGroup.generateSixDigitCode();
    final secret = BubbleGroup.generateSecret();
    final now = DateTime.now();
    final fallbackName = _nickname.isNotEmpty ? "$_nickname's Bubble" : 'Bubble #$code';

    final group = BubbleGroup(
      id: _uuid.v4(),
      code: code,
      secret: secret,
      name: (customName != null && customName.trim().isNotEmpty)
          ? customName.trim()
          : fallbackName,
      isCreator: true,
      joinedAt: now,
      lastSessionAt: now,
    );
    await upsertGroup(group);
    return group;
  }

  Future<BubbleGroup> joinFromInvite(BubbleInvitePayload invite) async {
    final existing = _groups.where((g) => g.code == invite.code).firstOrNull;
    final now = DateTime.now();
    final group = existing != null
        ? existing.copyWith(lastSessionAt: now)
        : BubbleGroup(
            id: invite.groupId,
            code: invite.code,
            secret: invite.secret,
            name: invite.name,
            isCreator: false,
            joinedAt: now,
            lastSessionAt: now,
          );
    await upsertGroup(group);
    return group;
  }

  Future<void> upsertGroup(BubbleGroup group) async {
    _groups = [
      group,
      ..._groups.where((g) => g.code != group.code),
    ]..sort((a, b) => b.lastSessionAt.compareTo(a.lastSessionAt));
    await _persistGroups();
    notifyListeners();
  }

  Future<void> markSessionVisited(String code) async {
    final idx = _groups.indexWhere((g) => g.code == code);
    if (idx == -1) return;
    final updated = _groups[idx].copyWith(lastSessionAt: DateTime.now());
    await upsertGroup(updated);
  }

  Future<void> renameGroup(String code, String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return;
    final idx = _groups.indexWhere((g) => g.code == code);
    if (idx == -1) return;
    await upsertGroup(_groups[idx].copyWith(name: trimmed));
  }

  Future<void> toggleMuteGroup(String code) async {
    final idx = _groups.indexWhere((g) => g.code == code);
    if (idx == -1) return;
    await upsertGroup(_groups[idx].copyWith(muted: !_groups[idx].muted));
  }

  Future<void> abandonGroup(String code) async {
    _groups = _groups.where((g) => g.code != code).toList();
    await _persistGroups();
    notifyListeners();
  }

  Future<void> _persistGroups() async {
    _prefs ??= await SharedPreferences.getInstance();
    final encoded = jsonEncode(_groups.map((g) => g.toJson()).toList());
    await _prefs!.setString(_kGroupsKey, encoded);
  }
}
