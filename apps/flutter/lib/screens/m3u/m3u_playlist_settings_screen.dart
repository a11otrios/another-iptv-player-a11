import 'package:flutter/material.dart';
import 'package:another_iptv_player/models/category_view_model.dart';
import 'package:another_iptv_player/models/playlist_model.dart';
import 'package:another_iptv_player/l10n/localization_extension.dart';
import '../../widgets/playlist_info_widget.dart';
import '../settings/category_settings_section.dart';
import '../settings/general_settings_section.dart';

class M3uPlaylistSettingsScreen extends StatefulWidget {
  final Playlist playlist;
  final List<CategoryViewModel> liveCategories;
  final List<CategoryViewModel> movieCategories;
  final List<CategoryViewModel> seriesCategories;
  final Future<void> Function()? onCategoryVisibilityChanged;

  const M3uPlaylistSettingsScreen({
    super.key,
    required this.playlist,
    this.liveCategories = const [],
    this.movieCategories = const [],
    this.seriesCategories = const [],
    this.onCategoryVisibilityChanged,
  });

  @override
  State<M3uPlaylistSettingsScreen> createState() =>
      _N3uPlaylistSettingsScreenState();
}

class _N3uPlaylistSettingsScreenState extends State<M3uPlaylistSettingsScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: SelectableText(
          context.loc.settings,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        children: [
          const GeneralSettingsWidget(),
          const SizedBox(height: 16),
          _CategoryVisibilityCard(
            playlistId: widget.playlist.id,
            liveCategories: widget.liveCategories,
            movieCategories: widget.movieCategories,
            seriesCategories: widget.seriesCategories,
            onCategoryVisibilityChanged: widget.onCategoryVisibilityChanged,
          ),
          const SizedBox(height: 16),
          PlaylistInfoWidget(playlist: widget.playlist),
        ],
      ),
    );
  }
}

class _CategoryVisibilityCard extends StatelessWidget {
  final String playlistId;
  final List<CategoryViewModel> liveCategories;
  final List<CategoryViewModel> movieCategories;
  final List<CategoryViewModel> seriesCategories;
  final Future<void> Function()? onCategoryVisibilityChanged;

  const _CategoryVisibilityCard({
    required this.playlistId,
    required this.liveCategories,
    required this.movieCategories,
    required this.seriesCategories,
    this.onCategoryVisibilityChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.visibility_off_outlined),
        title: Text(context.loc.manage_categories),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          final changed = await Navigator.push<bool>(
            context,
            MaterialPageRoute(
              builder: (context) => CategorySettingsScreen(
                playlistId: playlistId,
                liveCategories: liveCategories,
                movieCategories: movieCategories,
                seriesCategories: seriesCategories,
              ),
            ),
          );
          if (changed == true) {
            await onCategoryVisibilityChanged?.call();
          }
        },
      ),
    );
  }
}
