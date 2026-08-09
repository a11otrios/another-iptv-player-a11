import 'package:another_iptv_player/l10n/app_localizations.dart';
import 'package:another_iptv_player/services/legacy_data_migration_service.dart';
import 'package:another_iptv_player/services/lan_server/lan_server_controller.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:another_iptv_player/database/database.dart';
import 'package:another_iptv_player/utils/audio_handler.dart';
import 'package:media_kit/media_kit.dart';

GetIt getIt = GetIt.instance;

Future<void> setupServiceLocator() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await LegacyDataMigrationService.migrateIfNeeded();
  } catch (error) {
    debugPrint('Continuing without legacy data import: $error');
  }

  getIt.registerSingleton<MyAudioHandler>(await initAudioService());
  getIt.registerSingleton<AppDatabase>(AppDatabase());
  getIt.registerSingleton<LanServerController>(LanServerController.instance);

  MediaKit.ensureInitialized();
}

void setupLocator(BuildContext context) {
  getIt.registerSingleton<AppLocalizations>(AppLocalizations.of(context)!);
}
