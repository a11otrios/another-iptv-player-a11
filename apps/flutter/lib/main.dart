import 'package:another_iptv_player/controllers/playlist_controller.dart';
import 'package:another_iptv_player/database/database.dart';
import 'package:another_iptv_player/screens/app_initializer_screen.dart';
import 'package:another_iptv_player/services/desktop_window_controller.dart';
import 'package:another_iptv_player/services/lan_server/lan_server_controller.dart';
import 'package:another_iptv_player/widgets/desktop_window_frame.dart';
import 'package:flutter/material.dart';
import 'package:another_iptv_player/services/service_locator.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'controllers/locale_provider.dart';
import 'controllers/theme_provider.dart';
import 'l10n/app_localizations.dart';
import 'l10n/supported_languages.dart';
import 'utils/app_themes.dart';

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  await setupServiceLocator();
  await LanServerController.instance.initialize(getIt<AppDatabase>());
  await DesktopWindowController.instance.initialize(
    borderlessOverride: arguments.contains('--borderless') ? true : null,
    alwaysOnTopOverride: arguments.contains('--always-on-top') ? true : null,
  );
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LocaleProvider()),
        ChangeNotifierProvider(create: (_) => PlaylistController()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider.value(value: DesktopWindowController.instance),
        ChangeNotifierProvider.value(value: LanServerController.instance),
      ],
      child: const MyApp(),
    ),
  );

  WidgetsBinding.instance.addPostFrameCallback((_) {
    DesktopWindowController.instance.applySavedWindowState();
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final localeProvider = Provider.of<LocaleProvider>(context);
    final themeProvider = Provider.of<ThemeProvider>(context);

    return MaterialApp(
      locale: localeProvider.locale,
      supportedLocales: supportedLanguages
          .map((lang) => Locale(lang['code']))
          .toList(),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      title: 'Another IPTV Player',
      theme: AppThemes.lightTheme,
      darkTheme: AppThemes.darkTheme,
      themeMode: themeProvider.themeMode,
      builder: (context, child) =>
          DesktopWindowFrame(child: child ?? const SizedBox.shrink()),
      home: AppInitializerScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
