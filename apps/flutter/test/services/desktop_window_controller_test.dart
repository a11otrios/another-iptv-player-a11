import 'package:another_iptv_player/repositories/user_preferences.dart';
import 'package:another_iptv_player/services/desktop_window_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test/desktop_window');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    SharedPreferences.setMockInitialValues({
      'borderless_window': true,
      'always_on_top': true,
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'isMaximized') return false;
          if (call.method == 'toggleMaximized') return true;
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('restores, applies, and persists independent window modes', () async {
    final controller = DesktopWindowController(
      channel: channel,
      isSupportedOverride: true,
    );
    addTearDown(controller.dispose);

    await controller.initialize();

    expect(controller.borderless, isTrue);
    expect(controller.alwaysOnTop, isTrue);
    expect(calls.map((call) => call.method), ['isMaximized']);

    await controller.applySavedWindowState();

    expect(calls.map((call) => call.method), [
      'isMaximized',
      'setBorderless',
      'setAlwaysOnTop',
    ]);

    await controller.setBorderless(false);
    await controller.setAlwaysOnTop(false);
    await controller.toggleMaximized();

    expect(controller.borderless, isFalse);
    expect(controller.alwaysOnTop, isFalse);
    expect(controller.isMaximized, isTrue);
    expect(await UserPreferences.getBorderlessWindow(), isFalse);
    expect(await UserPreferences.getAlwaysOnTop(), isFalse);
  });
}
