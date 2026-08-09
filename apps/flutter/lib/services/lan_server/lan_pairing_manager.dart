import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

class PairedLanDevice {
  const PairedLanDevice({
    required this.id,
    required this.name,
    required this.token,
    required this.pairedAt,
    required this.lastSeenAt,
  });

  final String id;
  final String name;
  final String token;
  final DateTime pairedAt;
  final DateTime lastSeenAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'token': token,
    'pairedAt': pairedAt.toUtc().toIso8601String(),
    'lastSeenAt': lastSeenAt.toUtc().toIso8601String(),
  };

  factory PairedLanDevice.fromJson(Map<String, Object?> json) {
    return PairedLanDevice(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'LG TV',
      token: json['token'] as String? ?? '',
      pairedAt:
          DateTime.tryParse(json['pairedAt'] as String? ?? '') ??
          DateTime.now(),
      lastSeenAt:
          DateTime.tryParse(json['lastSeenAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

class LanPairingManager {
  LanPairingManager({Random? random}) : _random = random ?? Random.secure();

  static const _devicesKey = 'lan_server_paired_devices_v1';
  static const pairingLifetime = Duration(minutes: 10);

  final Random _random;
  final List<PairedLanDevice> _devices = [];
  String _code = '';
  DateTime _codeExpiresAt = DateTime.fromMillisecondsSinceEpoch(0);

  String get pairingCode {
    if (!pairingAvailable) rotateCode();
    return _code;
  }

  DateTime get pairingCodeExpiresAt => _codeExpiresAt;
  bool get pairingAvailable =>
      _code.isNotEmpty && DateTime.now().isBefore(_codeExpiresAt);
  List<PairedLanDevice> get devices => List.unmodifiable(_devices);

  Future<void> initialize() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_devicesKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          _devices
            ..clear()
            ..addAll(
              decoded
                  .whereType<Map>()
                  .map(
                    (item) => PairedLanDevice.fromJson(
                      Map<String, Object?>.from(item),
                    ),
                  )
                  .where((item) => item.id.isNotEmpty && item.token.isNotEmpty),
            );
        }
      } catch (_) {
        // A damaged preference should not prevent the server from starting.
      }
    }
    rotateCode();
  }

  void rotateCode() {
    _code = (100000 + _random.nextInt(900000)).toString();
    _codeExpiresAt = DateTime.now().add(pairingLifetime);
  }

  Future<PairedLanDevice> pair({
    required String code,
    required String deviceName,
  }) async {
    if (!pairingAvailable || code != _code) {
      throw const PairingRejectedException();
    }
    final now = DateTime.now().toUtc();
    final device = PairedLanDevice(
      id: _randomToken(12),
      name: deviceName.trim().isEmpty ? 'LG TV' : deviceName.trim(),
      token: _randomToken(32),
      pairedAt: now,
      lastSeenAt: now,
    );
    _devices.add(device);
    _code = '';
    _codeExpiresAt = DateTime.fromMillisecondsSinceEpoch(0);
    await _save();
    return device;
  }

  bool accepts(String token) =>
      token.isNotEmpty &&
      _devices.any((device) => _constantTimeEquals(device.token, token));

  Future<bool> acceptsAndTouch(String token) async {
    if (token.isEmpty) return false;
    final index = _devices.indexWhere(
      (device) => _constantTimeEquals(device.token, token),
    );
    if (index < 0) return false;
    final now = DateTime.now().toUtc();
    final current = _devices[index];
    if (now.difference(current.lastSeenAt).inMinutes >= 1) {
      _devices[index] = PairedLanDevice(
        id: current.id,
        name: current.name,
        token: current.token,
        pairedAt: current.pairedAt,
        lastSeenAt: now,
      );
      await _save();
    }
    return true;
  }

  Future<void> revoke(String deviceId) async {
    _devices.removeWhere((device) => device.id == deviceId);
    await _save();
  }

  Future<void> _save() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _devicesKey,
      jsonEncode(_devices.map((device) => device.toJson()).toList()),
    );
  }

  String _randomToken(int bytes) {
    final values = List<int>.generate(bytes, (_) => _random.nextInt(256));
    return base64UrlEncode(values).replaceAll('=', '');
  }
}

class PairingRejectedException implements Exception {
  const PairingRejectedException();
}

bool _constantTimeEquals(String left, String right) {
  if (left.length != right.length) return false;
  var result = 0;
  for (var i = 0; i < left.length; i++) {
    result |= left.codeUnitAt(i) ^ right.codeUnitAt(i);
  }
  return result == 0;
}
