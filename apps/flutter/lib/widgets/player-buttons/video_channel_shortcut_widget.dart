import 'dart:async';

import 'package:another_iptv_player/models/content_type.dart';
import 'package:another_iptv_player/models/playlist_content_model.dart';
import 'package:another_iptv_player/services/channel_shortcut_service.dart';
import 'package:another_iptv_player/services/event_bus.dart';
import 'package:another_iptv_player/services/player_state.dart';
import 'package:flutter/material.dart';

class VideoChannelShortcutWidget extends StatefulWidget {
  const VideoChannelShortcutWidget({super.key});

  @override
  State<VideoChannelShortcutWidget> createState() =>
      _VideoChannelShortcutWidgetState();
}

class _VideoChannelShortcutWidgetState
    extends State<VideoChannelShortcutWidget> {
  final ChannelShortcutService _shortcutService = ChannelShortcutService();
  StreamSubscription<ContentItem>? _contentSubscription;
  String _selectedPage = ChannelShortcutService.defaultPage;

  @override
  void initState() {
    super.initState();
    _contentSubscription = EventBus()
        .on<ContentItem>('player_content_item')
        .listen((_) {
          if (mounted) setState(() {});
        });
  }

  @override
  void dispose() {
    _contentSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentContent = PlayerState.currentContent;
    if (currentContent?.contentType != ContentType.liveStream) {
      return const SizedBox.shrink();
    }

    return IconButton(
      tooltip: 'Assign channel number',
      icon: const Icon(Icons.dialpad, color: Colors.white),
      onPressed: () => _showShortcutDialog(currentContent!),
    );
  }

  Future<void> _showShortcutDialog(ContentItem currentContent) async {
    final shortcutsByPage = <String, Map<int, ContentItem>>{
      for (final page in ChannelShortcutService.pages)
        page: await _shortcutService.getShortcutsForPage(page),
    };
    if (!mounted) return;

    final assignment = await showDialog<_ShortcutAssignment>(
      context: context,
      builder: (dialogContext) {
        var selectedPage = _selectedPage;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final shortcuts = shortcutsByPage[selectedPage]!;
            return AlertDialog(
              title: const Text('Assign channel shortcut'),
              content: SizedBox(
                width: 420,
                height: 470,
                child: Column(
                  children: [
                    SegmentedButton<String>(
                      segments: [
                        for (final page in ChannelShortcutService.pages)
                          ButtonSegment<String>(value: page, label: Text(page)),
                      ],
                      selected: {selectedPage},
                      showSelectedIcon: false,
                      onSelectionChanged: (selection) {
                        setDialogState(() {
                          selectedPage = selection.first;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ListView.builder(
                        itemCount: 10,
                        itemBuilder: (context, number) {
                          final assignedChannel = shortcuts[number];
                          final isCurrent =
                              assignedChannel?.id == currentContent.id;

                          return ListTile(
                            dense: true,
                            leading: CircleAvatar(
                              radius: 18,
                              child: Text('$selectedPage$number'),
                            ),
                            title: Text(
                              assignedChannel?.name ?? 'Unassigned',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: assignedChannel == null
                                ? null
                                : Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (isCurrent)
                                        const Icon(
                                          Icons.check,
                                          color: Colors.green,
                                        ),
                                      IconButton(
                                        tooltip: 'Clear assignment',
                                        icon: const Icon(Icons.clear),
                                        onPressed: () async {
                                          await _shortcutService.removeShortcut(
                                            number,
                                            page: selectedPage,
                                          );
                                          if (!dialogContext.mounted) return;
                                          shortcuts.remove(number);
                                          setDialogState(() {});
                                        },
                                      ),
                                    ],
                                  ),
                            onTap: () => Navigator.pop(
                              dialogContext,
                              _ShortcutAssignment(selectedPage, number),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
              ],
            );
          },
        );
      },
    );

    if (assignment == null) return;
    _selectedPage = assignment.page;
    await _shortcutService.assignShortcut(
      assignment.number,
      currentContent,
      page: assignment.page,
    );
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            '${assignment.page}${assignment.number} now opens ${currentContent.name}',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
  }
}

class _ShortcutAssignment {
  final String page;
  final int number;

  const _ShortcutAssignment(this.page, this.number);
}
