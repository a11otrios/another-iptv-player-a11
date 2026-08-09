import 'dart:io';

import 'package:another_iptv_player/database/database.dart';
import 'package:another_iptv_player/screens/settings/subtitle_settings_section.dart';
import 'package:another_iptv_player/services/desktop_window_controller.dart';
import 'package:another_iptv_player/services/portable_playlist_transfer_service.dart';
import 'package:another_iptv_player/services/service_locator.dart';
import 'package:another_iptv_player/utils/get_playlist_type.dart';
import 'package:another_iptv_player/utils/show_loading_dialog.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:another_iptv_player/l10n/localization_extension.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../controllers/locale_provider.dart';
import '../../controllers/theme_provider.dart';
import '../../l10n/supported_languages.dart';
import '../../models/m3u_item.dart';
import '../../repositories/user_preferences.dart';
import '../../services/app_state.dart';
import '../../services/m3u_parser.dart';
import '../../widgets/dropdown_tile_widget.dart';
import '../../widgets/lan_server_settings_card.dart';
import '../../widgets/section_title_widget.dart';
import '../m3u/m3u_data_loader_screen.dart';
import '../playlist_screen.dart';
import '../xtream-codes/xtream_code_data_loader_screen.dart';

class GeneralSettingsWidget extends StatefulWidget {
  const GeneralSettingsWidget({super.key});

  @override
  State<GeneralSettingsWidget> createState() => _GeneralSettingsWidgetState();
}

class _GeneralSettingsWidgetState extends State<GeneralSettingsWidget> {
  final AppDatabase database = getIt<AppDatabase>();

  bool _backgroundPlayEnabled = false;
  bool _isLoading = true;
  String? _selectedFilePath;
  String _selectedTheme = 'system';
  bool _brightnessGesture = false;
  bool _volumeGesture = false;
  bool _seekGesture = false;
  bool _speedUpOnLongPress = true;
  bool _seekOnDoubleTap = true;
  bool _isTransferring = false;
  String _appVersion = '';
  String _openSubtitlesApiKey = '';
  String _openSubtitlesUsername = '';
  String _openSubtitlesLanguages = 'en';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final backgroundPlay = await UserPreferences.getBackgroundPlay();
      final themeMode = await UserPreferences.getThemeMode();
      final brightnessGesture = await UserPreferences.getBrightnessGesture();
      final volumeGesture = await UserPreferences.getVolumeGesture();
      final seekGesture = await UserPreferences.getSeekGesture();
      final speedUpOnLongPress = await UserPreferences.getSpeedUpOnLongPress();
      final seekOnDoubleTap = await UserPreferences.getSeekOnDoubleTap();
      final openSubtitlesApiKey =
          await UserPreferences.getOpenSubtitlesApiKey();
      final openSubtitlesUsername =
          await UserPreferences.getOpenSubtitlesUsername();
      final openSubtitlesLanguages =
          await UserPreferences.getOpenSubtitlesLanguages();
      final packageInfo = await PackageInfo.fromPlatform();
      setState(() {
        _backgroundPlayEnabled = backgroundPlay;
        _selectedTheme = _themeModeToString(themeMode);
        _brightnessGesture = brightnessGesture;
        _volumeGesture = volumeGesture;
        _seekGesture = seekGesture;
        _speedUpOnLongPress = speedUpOnLongPress;
        _seekOnDoubleTap = seekOnDoubleTap;
        _openSubtitlesApiKey = openSubtitlesApiKey;
        _openSubtitlesUsername = openSubtitlesUsername;
        _openSubtitlesLanguages = openSubtitlesLanguages;
        _appVersion = packageInfo.version;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  String _themeModeToString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      default:
        return 'system';
    }
  }

  ThemeMode _stringToThemeMode(String value) {
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  Future<void> _saveBackgroundPlaySetting(bool value) async {
    try {
      await UserPreferences.setBackgroundPlay(value);
      setState(() {
        _backgroundPlayEnabled = value;
      });
    } catch (e) {
      setState(() {
        _backgroundPlayEnabled = !value;
      });
    }
  }

  Future<void> _updateDesktopWindowSetting(
    Future<void> Function() update,
  ) async {
    try {
      await update();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(
            content: Text('Could not update the Windows display mode.'),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final desktopWindowController = Provider.of<DesktopWindowController>(
      context,
    );
    return _isLoading
        ? const Center(child: CircularProgressIndicator())
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Card(
                child: ListTile(
                  leading: const Icon(Icons.home),
                  title: Text(context.loc.playlist_list),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await UserPreferences.removeLastPlaylist();
                    if (context.mounted) {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (context) => PlaylistScreen(),
                        ),
                      );
                    }
                  },
                ),
              ),
              const SizedBox(height: 10),
              SectionTitleWidget(title: context.loc.general_settings),
              const LanServerSettingsCard(),
              const SizedBox(height: 10),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.refresh),
                      title: Text(context.loc.refresh_contents),
                      trailing: const Icon(Icons.cloud_download),
                      onTap: () {
                        if (isXtreamCode) {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (context) => XtreamCodeDataLoaderScreen(
                                playlist: AppState.currentPlaylist!,
                                refreshAll: true,
                              ),
                            ),
                          );
                        }

                        if (isM3u) {
                          refreshM3uPlaylist();
                        }
                      },
                    ),
                    const Divider(height: 1),
                    DropdownTileWidget<Locale>(
                      icon: Icons.language,
                      label: context.loc.app_language,
                      value: Localizations.localeOf(context),
                      items: [
                        ...supportedLanguages.map(
                          (language) => DropdownMenuItem(
                            value: Locale(language['code']),
                            child: Text(language['name']),
                          ),
                        ),
                      ],
                      onChanged: (v) {
                        Provider.of<LocaleProvider>(
                          context,
                          listen: false,
                        ).setLocale(v!);
                      },
                    ),
                    const Divider(height: 1),
                    DropdownTileWidget<String>(
                      icon: Icons.color_lens_outlined,
                      label: context.loc.theme,
                      value: _selectedTheme,
                      items: [
                        DropdownMenuItem(
                          value: 'system',
                          child: Text(context.loc.standard),
                        ),
                        DropdownMenuItem(
                          value: 'light',
                          child: Text(context.loc.light),
                        ),
                        DropdownMenuItem(
                          value: 'dark',
                          child: Text(context.loc.dark),
                        ),
                      ],
                      onChanged: (value) async {
                        if (value != null) {
                          final themeMode = _stringToThemeMode(value);
                          await themeProvider.setTheme(themeMode);
                          setState(() {
                            _selectedTheme = value;
                          });
                        }
                      },
                    ),
                    if (desktopWindowController.isSupported) ...[
                      const Divider(height: 1),
                      SwitchListTile(
                        secondary: const Icon(Icons.crop_free),
                        title: const Text('Borderless window'),
                        subtitle: const Text(
                          'Replace the Windows frame with compact app controls.',
                        ),
                        value: desktopWindowController.borderless,
                        onChanged: (value) => _updateDesktopWindowSetting(
                          () => desktopWindowController.setBorderless(value),
                        ),
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        secondary: const Icon(Icons.push_pin_outlined),
                        title: const Text('Always on top'),
                        subtitle: const Text(
                          'Keep the player above other windows.',
                        ),
                        value: desktopWindowController.alwaysOnTop,
                        onChanged: (value) => _updateDesktopWindowSetting(
                          () => desktopWindowController.setAlwaysOnTop(value),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 10),
              const SectionTitleWidget(title: 'Favorites & channel numbers'),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.file_upload_outlined),
                      title: const Text('Export favorites & numbers'),
                      trailing: _isTransferring
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.chevron_right),
                      onTap: _isTransferring ? null : _exportPortableData,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.file_download_outlined),
                      title: const Text('Import favorites & numbers'),
                      trailing: _isTransferring
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.chevron_right),
                      onTap: _isTransferring ? null : _importPortableData,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              SectionTitleWidget(title: context.loc.player_settings),
              Card(
                child: Column(
                  children: [
                    SwitchListTile(
                      secondary: const Icon(Icons.play_circle_outline),
                      title: Text(context.loc.continue_on_background),
                      subtitle: Text(
                        context.loc.continue_on_background_description,
                      ),
                      value: _backgroundPlayEnabled,
                      onChanged: _saveBackgroundPlaySetting,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.subtitles_outlined),
                      title: Text(context.loc.subtitle_settings),
                      subtitle: Text(context.loc.subtitle_settings_description),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                const SubtitleSettingsScreen(),
                          ),
                        );
                      },
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.cloud_sync_outlined),
                      title: const Text('OpenSubtitles'),
                      subtitle: Text(
                        _openSubtitlesApiKey.isEmpty
                            ? 'Add your API key to search and download subtitles.'
                            : 'Signed in as ${_openSubtitlesUsername.isEmpty ? 'configured user' : _openSubtitlesUsername} • $_openSubtitlesLanguages',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _showOpenSubtitlesSettings,
                    ),
                    // Player gesture settings - Only show on mobile platforms (Android & iOS)
                    if (Theme.of(context).platform == TargetPlatform.android ||
                        Theme.of(context).platform == TargetPlatform.iOS) ...[
                      const Divider(height: 1),
                      SwitchListTile(
                        secondary: const Icon(Icons.brightness_6),
                        title: Text(context.loc.brightness_gesture),
                        subtitle: Text(
                          context.loc.brightness_gesture_description,
                        ),
                        value: _brightnessGesture,
                        onChanged: (value) async {
                          await UserPreferences.setBrightnessGesture(value);
                          setState(() {
                            _brightnessGesture = value;
                          });
                        },
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        secondary: const Icon(Icons.volume_up),
                        title: Text(context.loc.volume_gesture),
                        subtitle: Text(context.loc.volume_gesture_description),
                        value: _volumeGesture,
                        onChanged: (value) async {
                          await UserPreferences.setVolumeGesture(value);
                          setState(() {
                            _volumeGesture = value;
                          });
                        },
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        secondary: const Icon(Icons.swipe),
                        title: Text(context.loc.seek_gesture),
                        subtitle: Text(context.loc.seek_gesture_description),
                        value: _seekGesture,
                        onChanged: (value) async {
                          await UserPreferences.setSeekGesture(value);
                          setState(() {
                            _seekGesture = value;
                          });
                        },
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        secondary: const Icon(Icons.fast_forward),
                        title: Text(context.loc.speed_up_on_long_press),
                        subtitle: Text(
                          context.loc.speed_up_on_long_press_description,
                        ),
                        value: _speedUpOnLongPress,
                        onChanged: (value) async {
                          await UserPreferences.setSpeedUpOnLongPress(value);
                          setState(() {
                            _speedUpOnLongPress = value;
                          });
                        },
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        secondary: const Icon(Icons.touch_app),
                        title: Text(context.loc.seek_on_double_tap),
                        subtitle: Text(
                          context.loc.seek_on_double_tap_description,
                        ),
                        value: _seekOnDoubleTap,
                        onChanged: (value) async {
                          await UserPreferences.setSeekOnDoubleTap(value);
                          setState(() {
                            _seekOnDoubleTap = value;
                          });
                        },
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 10),
              SectionTitleWidget(title: context.loc.about),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.info_outline),
                      title: Text(context.loc.app_version),
                      subtitle: Text(
                        _appVersion.isNotEmpty ? _appVersion : 'Loading...',
                      ),
                      dense: true,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.code),
                      title: Text(context.loc.support_on_github),
                      subtitle: Text(context.loc.support_on_github_description),
                      trailing: const Icon(Icons.open_in_new, size: 18),
                      dense: true,
                      onTap: () async {
                        final url = Uri.parse(
                          'https://github.com/bsogulcan/another-iptv-player',
                        );
                        if (await canLaunchUrl(url)) {
                          await launchUrl(
                            url,
                            mode: LaunchMode.externalApplication,
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
            ],
          );
  }

  refreshM3uPlaylist() async {
    List<M3uItem> oldM3uItems = AppState.m3uItems!;
    List<M3uItem> newM3uItems = [];

    if (AppState.currentPlaylist!.url!.startsWith('http')) {
      showLoadingDialog(context, context.loc.loading_m3u);
      final params = {
        'id': AppState.currentPlaylist!.id,
        'url': AppState.currentPlaylist!.url!,
      };
      newM3uItems = await compute(M3uParser.parseM3uUrl, params);
    } else {
      await _pickFile();
      if (_selectedFilePath == null) return;
      if (!mounted) return;

      showLoadingDialog(context, context.loc.loading_m3u);
      final params = {
        'id': AppState.currentPlaylist!.id,
        'filePath': _selectedFilePath!,
      };
      newM3uItems = await compute(M3uParser.parseM3uFile, params);
    }

    newM3uItems = updateM3UItemIdsByPosition(
      oldItems: oldM3uItems,
      newItems: newM3uItems,
    );

    await database.deleteAllM3uItems(AppState.currentPlaylist!.id);
    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => M3uDataLoaderScreen(
          playlist: AppState.currentPlaylist!,
          m3uItems: newM3uItems,
        ),
      ),
    );
  }

  Future<void> _pickFile() async {
    _selectedFilePath = null;

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['m3u', 'm3u8'],
        allowMultiple: false,
      );

      if (result != null) {
        if (!mounted) return;
        setState(() {
          _selectedFilePath = result.files.single.path;
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.loc.file_selection_error)));
    }
  }

  Future<void> _showOpenSubtitlesSettings() async {
    final apiKeyController = TextEditingController(
      text: await UserPreferences.getOpenSubtitlesApiKey(),
    );
    final usernameController = TextEditingController(
      text: await UserPreferences.getOpenSubtitlesUsername(),
    );
    final passwordController = TextEditingController(
      text: await UserPreferences.getOpenSubtitlesPassword(),
    );
    final languagesController = TextEditingController(
      text: await UserPreferences.getOpenSubtitlesLanguages(),
    );

    if (!mounted) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('OpenSubtitles'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: apiKeyController,
                  decoration: const InputDecoration(
                    labelText: 'API key',
                    helperText: 'Create one in your OpenSubtitles profile.',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: usernameController,
                  decoration: const InputDecoration(labelText: 'Username'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Password'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: languagesController,
                  decoration: const InputDecoration(
                    labelText: 'Preferred languages',
                    helperText:
                        'Comma separated OpenSubtitles codes, e.g. en,es,pt-br',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.loc.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (saved != true) {
      apiKeyController.dispose();
      usernameController.dispose();
      passwordController.dispose();
      languagesController.dispose();
      return;
    }

    await UserPreferences.setOpenSubtitlesApiKey(apiKeyController.text);
    await UserPreferences.setOpenSubtitlesUsername(usernameController.text);
    await UserPreferences.setOpenSubtitlesPassword(passwordController.text);
    await UserPreferences.setOpenSubtitlesLanguages(languagesController.text);
    await UserPreferences.setOpenSubtitlesToken('');

    if (!mounted) return;
    setState(() {
      _openSubtitlesApiKey = apiKeyController.text.trim();
      _openSubtitlesUsername = usernameController.text.trim();
      _openSubtitlesLanguages = languagesController.text
          .split(',')
          .map((part) => part.trim().toLowerCase())
          .where((part) => part.isNotEmpty)
          .join(',');
    });

    apiKeyController.dispose();
    usernameController.dispose();
    passwordController.dispose();
    languagesController.dispose();
  }

  Future<void> _exportPortableData() async {
    final playlist = AppState.currentPlaylist;
    if (playlist == null) return;

    final safePlaylistName = playlist.name
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .trim();
    final selectedPath = await FilePicker.platform.saveFile(
      dialogTitle: 'Export favorites & channel numbers',
      fileName:
          'another-iptv-player-${safePlaylistName.isEmpty ? 'playlist' : safePlaylistName}.json',
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    if (selectedPath == null) return;

    _setTransferring(true);
    try {
      final json = await PortablePlaylistTransferService()
          .exportCurrentPlaylist();
      final outputPath = selectedPath.toLowerCase().endsWith('.json')
          ? selectedPath
          : '$selectedPath.json';
      await File(outputPath).writeAsString(json, flush: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Favorites and channel numbers exported')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Export failed: $error')));
    } finally {
      _setTransferring(false);
    }
  }

  Future<void> _importPortableData() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Import favorites & channel numbers',
      type: FileType.custom,
      allowedExtensions: const ['json'],
      allowMultiple: false,
    );
    final selectedPath = result?.files.single.path;
    if (selectedPath == null) return;

    _setTransferring(true);
    try {
      final file = File(selectedPath);
      if (await file.length() > 5 * 1024 * 1024) {
        throw const FormatException('The selected backup is too large.');
      }
      final importResult = await PortablePlaylistTransferService()
          .importIntoCurrentPlaylist(await file.readAsString());
      if (!mounted) return;
      await _showImportResult(importResult);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Import failed: $error')));
    } finally {
      _setTransferring(false);
    }
  }

  void _setTransferring(bool value) {
    if (!mounted) return;
    setState(() {
      _isTransferring = value;
    });
  }

  Future<void> _showImportResult(PortableImportResult result) async {
    final details = <String>[
      '${result.favoritesAdded} favorites added',
      '${result.favoritesAlreadyPresent} favorites already present',
      '${result.channelNumbersAssigned} channel numbers assigned',
      '${result.hiddenCategoriesImported} hidden categories imported',
      '${result.categoryOrderImported} category positions imported',
      if (result.unmatchedNames.isNotEmpty)
        '${result.unmatchedNames.length} not found: '
            '${result.unmatchedNames.take(12).join(', ')}',
      if (result.ambiguousNames.isNotEmpty)
        '${result.ambiguousNames.length} ambiguous: '
            '${result.ambiguousNames.take(12).join(', ')}',
    ];

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Import complete'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SelectableText(details.join('\n\n')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  List<M3uItem> updateM3UItemIdsByPosition({
    required List<M3uItem> oldItems,
    required List<M3uItem> newItems,
  }) {
    Map<String, List<MapEntry<int, String>>> groupedOldItems = {};
    for (int i = 0; i < oldItems.length; i++) {
      M3uItem item = oldItems[i];
      String key = "${item.url}|||${item.name}";
      groupedOldItems.putIfAbsent(key, () => []);
      groupedOldItems[key]!.add(MapEntry(i, item.id));
    }

    Map<String, int> groupUsageCounter = {};
    List<M3uItem> updatedItems = [];

    for (int i = 0; i < newItems.length; i++) {
      M3uItem newItem = newItems[i];
      String key = "${newItem.url}|||${newItem.name}";

      if (groupedOldItems.containsKey(key)) {
        List<MapEntry<int, String>> oldGroup = groupedOldItems[key]!;
        int usageCount = groupUsageCounter[key] ?? 0;

        if (usageCount < oldGroup.length) {
          String oldId = oldGroup[usageCount].value;
          updatedItems.add(newItem.copyWith(id: oldId));
          groupUsageCounter[key] = usageCount + 1;
        } else {
          updatedItems.add(newItem);
        }
      } else {
        updatedItems.add(newItem);
      }
    }

    return updatedItems;
  }
}
