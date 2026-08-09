import 'dart:io';

import 'package:another_iptv_player/services/legacy_data_migration_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory temporaryDirectory;
  late Directory legacyDirectory;
  late Directory targetDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'another-iptv-player-migration-',
    );
    legacyDirectory = Directory(p.join(temporaryDirectory.path, 'legacy'));
    targetDirectory = Directory(p.join(temporaryDirectory.path, 'target'));
    await legacyDirectory.create();
    await targetDirectory.create();
  });

  tearDown(() async {
    await temporaryDirectory.delete(recursive: true);
  });

  test(
    'imports legacy database and settings once without changing source',
    () async {
      final legacyDatabase = File(
        p.join(legacyDirectory.path, 'another-iptv-player.sqlite'),
      );
      final targetDatabase = File(
        p.join(targetDirectory.path, 'another-iptv-player.sqlite'),
      );
      _createDatabase(legacyDatabase, playlistId: 'legacy-playlist');
      _createDatabase(targetDatabase);

      final legacyDatabaseBytes = await legacyDatabase.readAsBytes();
      await File(
        p.join(legacyDirectory.path, 'shared_preferences.json'),
      ).writeAsString('{"flutter.last_playlist":"legacy-playlist"}');
      await File(
        p.join(legacyDirectory.path, 'libCachedImageData.json'),
      ).writeAsString('{"cache":"legacy"}');

      final result = await LegacyDataMigrationService.migrateIfNeeded(
        legacyDirectory: legacyDirectory,
        targetDirectory: targetDirectory,
      );

      expect(result.status, LegacyDataMigrationStatus.imported);
      expect(result.playlistCount, 1);
      expect(_playlistIds(targetDatabase), ['legacy-playlist']);
      expect(await legacyDatabase.readAsBytes(), legacyDatabaseBytes);
      expect(
        await File(
          p.join(targetDirectory.path, 'shared_preferences.json'),
        ).readAsString(),
        '{"flutter.last_playlist":"legacy-playlist"}',
      );
      expect(
        await File(
          p.join(targetDirectory.path, 'libCachedImageData.json'),
        ).readAsString(),
        '{"cache":"legacy"}',
      );
      expect(
        await File(
          p.join(targetDirectory.path, '.legacy-import-v1-complete'),
        ).exists(),
        isTrue,
      );
      expect(
        targetDirectory
            .listSync()
            .where((entity) => entity.path.contains('.pre-legacy-import-'))
            .length,
        1,
      );

      final secondResult = await LegacyDataMigrationService.migrateIfNeeded(
        legacyDirectory: legacyDirectory,
        targetDirectory: targetDirectory,
      );

      expect(secondResult.status, LegacyDataMigrationStatus.alreadyCompleted);
      expect(_playlistIds(targetDatabase), ['legacy-playlist']);
    },
  );

  test('does not overwrite an existing populated target database', () async {
    final legacyDatabase = File(
      p.join(legacyDirectory.path, 'another-iptv-player.sqlite'),
    );
    final targetDatabase = File(
      p.join(targetDirectory.path, 'another-iptv-player.sqlite'),
    );
    _createDatabase(legacyDatabase, playlistId: 'legacy-playlist');
    _createDatabase(targetDatabase, playlistId: 'current-playlist');

    final result = await LegacyDataMigrationService.migrateIfNeeded(
      legacyDirectory: legacyDirectory,
      targetDirectory: targetDirectory,
    );

    expect(result.status, LegacyDataMigrationStatus.skippedExistingData);
    expect(_playlistIds(targetDatabase), ['current-playlist']);
    expect(_playlistIds(legacyDatabase), ['legacy-playlist']);
    expect(
      await File(
        p.join(targetDirectory.path, '.legacy-import-v1-complete'),
      ).exists(),
      isTrue,
    );
  });
}

void _createDatabase(File file, {String? playlistId}) {
  final database = sqlite3.open(file.path);
  try {
    database.execute(
      'CREATE TABLE playlists ('
      'id TEXT PRIMARY KEY NOT NULL, '
      'name TEXT NOT NULL'
      ')',
    );
    if (playlistId != null) {
      database.execute('INSERT INTO playlists (id, name) VALUES (?, ?)', [
        playlistId,
        'Test playlist',
      ]);
    }
  } finally {
    database.dispose();
  }
}

List<String> _playlistIds(File file) {
  final database = sqlite3.open(file.path, mode: OpenMode.readOnly);
  try {
    return database
        .select('SELECT id FROM playlists ORDER BY id')
        .map((row) => row['id'] as String)
        .toList();
  } finally {
    database.dispose();
  }
}
