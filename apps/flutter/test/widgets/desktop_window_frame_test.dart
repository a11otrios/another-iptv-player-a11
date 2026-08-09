import 'package:another_iptv_player/services/desktop_window_controller.dart';
import 'package:another_iptv_player/widgets/desktop_window_frame.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test/desktop_window_frame');

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'borderless_window': true,
      'always_on_top': true,
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'isMaximized') return false;
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('borderless frame provides recovery window controls', (
    tester,
  ) async {
    final controller = DesktopWindowController(
      channel: channel,
      isSupportedOverride: true,
    );
    addTearDown(controller.dispose);
    await controller.initialize();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: MaterialApp(
          builder: (context, child) =>
              DesktopWindowFrame(child: child ?? const SizedBox.shrink()),
          home: const Scaffold(body: Text('Player content')),
        ),
      ),
    );

    expect(find.text('Another IPTV Player'), findsOneWidget);
    expect(find.byIcon(Icons.push_pin), findsOneWidget);
    expect(find.byIcon(Icons.web_asset), findsOneWidget);
    expect(find.byIcon(Icons.remove), findsOneWidget);
    expect(find.byIcon(Icons.crop_square), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byIcon(Icons.web_asset));
    await tester.pumpAndSettle();

    expect(controller.borderless, isFalse);
    expect(find.text('Another IPTV Player'), findsNothing);
    expect(find.text('Player content'), findsOneWidget);
  });
}
