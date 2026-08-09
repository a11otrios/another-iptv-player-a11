import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

enum LegacyDataMigrationStatus {
  imported,
  alreadyCompleted,
  noLegacyData,
  skippedExistingData,
  unsupportedPlatform,
}

class LegacyDataMigrationResult {
  const LegacyDataMigrationResult(this.status, {this.playlistCount = 0});

  final LegacyDataMigrationStatus status;
  final int playlistCount;
}

class LegacyDataMigrationService {
  static const _databaseName = 'another-iptv-player.sqlite';
  static const _preferencesName = 'shared_preferences.json';
  static const _imageCacheName = 'libCachedImageData.json';
  static const _markerName = '.legacy-import-v1-complete';

  static Future<LegacyDataMigrationResult> migrateIfNeeded({
    Directory? legacyDirectory,
    Directory? targetDirectory,
  }) async {
    final hasExplicitDirectories =
        legacyDirectory != null && targetDirectory != null;
    if (!Platform.isWindows && !hasExplicitDirectories) {
      return const LegacyDataMigrationResult(
        LegacyDataMigrationStatus.unsupportedPlatform,
      );
    }

    final target = targetDirectory ?? await getApplicationSupportDirectory();
    final legacy = legacyDirectory ?? _defaultLegacyDirectory();
    if (legacy == null) {
      return const LegacyDataMigrationResult(
        LegacyDataMigrationStatus.noLegacyData,
      );
    }

    await target.create(recursive: true);

    final marker = File(p.join(target.path, _markerName));
    if (await marker.exists()) {
      return const LegacyDataMigrationResult(
        LegacyDataMigrationStatus.alreadyCompleted,
      );
    }

    final legacyDatabase = File(p.join(legacy.path, _databaseName));
    if (!await legacyDatabase.exists()) {
      return const LegacyDataMigrationResult(
        LegacyDataMigrationStatus.noLegacyData,
      );
    }

    final legacyPlaylistCount = _playlistCount(legacyDatabase);
    if (legacyPlaylistCount == 0) {
      return const LegacyDataMigrationResult(
        LegacyDataMigrationStatus.noLegacyData,
      );
    }

    final targetDatabase = File(p.join(target.path, _databaseName));
    if (await targetDatabase.exists() && _playlistCount(targetDatabase) > 0) {
      await _writeMarker(
        marker,
        status: 'skipped_existing_data',
        playlistCount: legacyPlaylistCount,
      );
      return LegacyDataMigrationResult(
        LegacyDataMigrationStatus.skippedExistingData,
        playlistCount: legacyPlaylistCount,
      );
    }

    final timestamp = DateTime.now().toUtc().microsecondsSinceEpoch;
    final migrations = <_FileMigration>[
      _FileMigration(
        source: legacyDatabase,
        target: targetDatabase,
        staging: File(
          '${targetDatabase.path}.legacy-import-$timestamp.staging',
        ),
        backup: File(
          '${targetDatabase.path}.pre-legacy-import-$timestamp.backup',
        ),
      ),
    ];

    for (final fileName in [_preferencesName, _imageCacheName]) {
      final source = File(p.join(legacy.path, fileName));
      if (await source.exists()) {
        final destination = File(p.join(target.path, fileName));
        migrations.add(
          _FileMigration(
            source: source,
            target: destination,
            staging: File(
              '${destination.path}.legacy-import-$timestamp.staging',
            ),
            backup: File(
              '${destination.path}.pre-legacy-import-$timestamp.backup',
            ),
          ),
        );
      }
    }

    try {
      await _stageDatabaseBackup(
        source: migrations.first.source,
        destination: migrations.first.staging,
      );
      final stagedPlaylistCount = _playlistCount(migrations.first.staging);
      if (stagedPlaylistCount != legacyPlaylistCount) {
        throw StateError(
          'The staged database did not contain the expected playlists.',
        );
      }

      for (final migration in migrations.skip(1)) {
        await migration.source.copy(migration.staging.path);
      }

      await _installStagedFiles(migrations);
      await _writeMarker(
        marker,
        status: 'imported',
        playlistCount: legacyPlaylistCount,
      );

      return LegacyDataMigrationResult(
        LegacyDataMigrationStatus.imported,
        playlistCount: legacyPlaylistCount,
      );
    } catch (error, stackTrace) {
      debugPrint('Legacy data import failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    } finally {
      for (final migration in migrations) {
        if (await migration.staging.exists()) {
          await migration.staging.delete();
        }
      }
    }
  }

  static Directory? _defaultLegacyDirectory() {
    final appData = Platform.environment['APPDATA'];
    if (appData == null || appData.isEmpty) {
      return null;
    }

    return Directory(p.join(appData, 'com.example', 'iptv_player'));
  }

  static int _playlistCount(File databaseFile) {
    Database? database;
    try {
      database = sqlite3.open(databaseFile.path, mode: OpenMode.readOnly);
      final result = database.select(
        'SELECT COUNT(*) AS playlist_count FROM playlists',
      );
      return result.first['playlist_count'] as int;
    } on SqliteException {
      return 0;
    } finally {
      database?.dispose();
    }
  }

  static Future<void> _stageDatabaseBackup({
    required File source,
    required File destination,
  }) async {
    if (await destination.exists()) {
      await destination.delete();
    }

    Database? sourceDatabase;
    Database? destinationDatabase;
    try {
      sourceDatabase = sqlite3.open(source.path, mode: OpenMode.readOnly);
      destinationDatabase = sqlite3.open(destination.path);
      await sourceDatabase
          .backup(destinationDatabase, nPage: 500)
          .drain<void>();
    } finally {
      destinationDatabase?.dispose();
      sourceDatabase?.dispose();
    }
  }

  static Future<void> _installStagedFiles(
    List<_FileMigration> migrations,
  ) async {
    final movedTargets = <_MovedFile>[];
    final installedTargets = <File>[];

    try {
      for (final migration in migrations) {
        if (await migration.target.exists()) {
          await migration.target.rename(migration.backup.path);
          movedTargets.add(
            _MovedFile(original: migration.target, backup: migration.backup),
          );
        }

        if (migration.target.path.endsWith(_databaseName)) {
          for (final suffix in ['-wal', '-shm']) {
            final sidecar = File('${migration.target.path}$suffix');
            if (await sidecar.exists()) {
              final sidecarBackup = File('${migration.backup.path}$suffix');
              await sidecar.rename(sidecarBackup.path);
              movedTargets.add(
                _MovedFile(original: sidecar, backup: sidecarBackup),
              );
            }
          }
        }
      }

      for (final migration in migrations) {
        await migration.staging.rename(migration.target.path);
        installedTargets.add(migration.target);
      }
    } catch (_) {
      for (final installed in installedTargets.reversed) {
        if (await installed.exists()) {
          await installed.delete();
        }
      }
      for (final moved in movedTargets.reversed) {
        if (await moved.backup.exists()) {
          await moved.backup.rename(moved.original.path);
        }
      }
      rethrow;
    }
  }

  static Future<void> _writeMarker(
    File marker, {
    required String status,
    required int playlistCount,
  }) async {
    final temporaryMarker = File('${marker.path}.staging');
    await temporaryMarker.writeAsString(
      jsonEncode({
        'status': status,
        'playlistCount': playlistCount,
        'completedAt': DateTime.now().toUtc().toIso8601String(),
      }),
      flush: true,
    );
    await temporaryMarker.rename(marker.path);
  }
}

class _FileMigration {
  const _FileMigration({
    required this.source,
    required this.target,
    required this.staging,
    required this.backup,
  });

  final File source;
  final File target;
  final File staging;
  final File backup;
}

class _MovedFile {
  const _MovedFile({required this.original, required this.backup});

  final File original;
  final File backup;
}
