import 'package:another_iptv_player/models/player_aspect_ratio_mode.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class VideoAspectRatioWidget extends StatelessWidget {
  final ValueListenable<PlayerAspectRatioMode> selectedModeListenable;
  final ValueChanged<PlayerAspectRatioMode> onChanged;

  const VideoAspectRatioWidget({
    super.key,
    required this.selectedModeListenable,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PlayerAspectRatioMode>(
      valueListenable: selectedModeListenable,
      builder: (context, selectedMode, child) {
        return PopupMenuButton<PlayerAspectRatioMode>(
          tooltip: 'Aspect ratio',
          icon: const Icon(Icons.aspect_ratio, color: Colors.white),
          initialValue: selectedMode,
          itemBuilder: (context) {
            return PlayerAspectRatioMode.values.map((mode) {
              return CheckedPopupMenuItem<PlayerAspectRatioMode>(
                value: mode,
                checked: mode == selectedMode,
                // Commit before the popup closes. The media controls may
                // unmount their button while this popup route is still visible.
                onTap: () => onChanged(mode),
                child: Text(mode.label),
              );
            }).toList();
          },
        );
      },
    );
  }
}
