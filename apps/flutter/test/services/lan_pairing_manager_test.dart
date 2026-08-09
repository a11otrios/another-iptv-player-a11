import 'package:another_iptv_player/services/lan_server/lan_pairing_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('pairs once, persists the token, and can revoke the device', () async {
    final manager = LanPairingManager();
    await manager.initialize();
    final code = manager.pairingCode;

    final device = await manager.pair(code: code, deviceName: 'Living Room');
    expect(device.name, 'Living Room');
    expect(manager.accepts(device.token), isTrue);
    expect(manager.pairingAvailable, isFalse);

    final restored = LanPairingManager();
    await restored.initialize();
    expect(restored.accepts(device.token), isTrue);
    expect(await restored.acceptsAndTouch(device.token), isTrue);
    expect(await restored.acceptsAndTouch('invalid-token'), isFalse);

    await restored.revoke(device.id);
    expect(restored.accepts(device.token), isFalse);
  });

  test('rejects an invalid pairing code', () async {
    final manager = LanPairingManager();
    await manager.initialize();
    expect(
      () => manager.pair(code: '000000', deviceName: 'TV'),
      throwsA(isA<PairingRejectedException>()),
    );
  });
}
