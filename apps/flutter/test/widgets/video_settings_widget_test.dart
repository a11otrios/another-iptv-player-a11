import 'package:another_iptv_player/l10n/app_localizations.dart';
import 'package:another_iptv_player/services/desktop_window_controller.dart';
import 'package:another_iptv_player/widgets/player-buttons/video_settings_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test/video_settings_window');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'isMaximized') return false;
          return null;
        });
  });

  tearDown(() {
    VideoSettingsWidget.hideOverlay();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('player settings can toggle always on top', (tester) async {
    final controller = DesktopWindowController(
      channel: channel,
      isSupportedOverride: true,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: const MaterialApp(
          locale: Locale('en'),
          supportedLocales: [Locale('en')],
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(body: VideoSettingsWidget()),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();

    expect(find.text('Window'), findsOneWidget);
    expect(find.text('Always on top'), findsOneWidget);

    await tester.tap(find.text('Always on top'));
    await tester.pumpAndSettle();

    expect(controller.alwaysOnTop, isTrue);
    expect(
      calls.any(
        (call) => call.method == 'setAlwaysOnTop' && call.arguments == true,
      ),
      isTrue,
    );
  });
}
