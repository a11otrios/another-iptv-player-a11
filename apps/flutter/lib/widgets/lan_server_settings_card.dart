import 'package:another_iptv_player/services/lan_server/lan_server_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

class LanServerSettingsCard extends StatelessWidget {
  const LanServerSettingsCard({super.key});

  @override
  Widget build(BuildContext context) {
    final server = context.watch<LanServerController>();
    final theme = Theme.of(context);
    final code = server.pairingCode;
    final primaryAddress = server.addresses.firstOrNull;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  server.running ? Icons.tv_rounded : Icons.tv_off_rounded,
                  color: server.running
                      ? theme.colorScheme.primary
                      : theme.colorScheme.error,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'LG webOS connection',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        server.running
                            ? 'Available to TVs on this network'
                            : server.error ?? 'Server is stopped',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (!server.running)
                  IconButton(
                    tooltip: 'Start server',
                    onPressed: server.start,
                    icon: const Icon(Icons.play_arrow_rounded),
                  ),
              ],
            ),
            if (server.running) ...[
              const Divider(height: 28),
              Text('TV address', style: theme.textTheme.labelLarge),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      primaryAddress ??
                          'No LAN address detected. Enter this computer\'s IP and port ${server.port}.',
                    ),
                  ),
                  if (primaryAddress != null)
                    IconButton(
                      tooltip: 'Copy address',
                      onPressed: () => Clipboard.setData(
                        ClipboardData(text: primaryAddress),
                      ),
                      icon: const Icon(Icons.copy_rounded),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Text('Pairing code', style: theme.textTheme.labelLarge),
              const SizedBox(height: 4),
              Row(
                children: [
                  SelectableText(
                    code.split('').join(' '),
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Generate a new code',
                    onPressed: server.refreshPairingCode,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
              Text(
                'Enter this code in the TV app. It expires at '
                '${TimeOfDay.fromDateTime(server.pairingCodeExpiresAt).format(context)}.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Icon(
                    server.ffmpegAvailable == true
                        ? Icons.check_circle_outline_rounded
                        : server.ffmpegAvailable == false
                        ? Icons.warning_amber_rounded
                        : Icons.hourglass_empty_rounded,
                    size: 20,
                    color: server.ffmpegAvailable == false
                        ? theme.colorScheme.error
                        : theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      server.ffmpegAvailable == true
                          ? 'Compatibility playback available'
                          : server.ffmpegAvailable == false
                          ? 'FFmpeg not found; direct and proxy playback remain available'
                          : 'Checking compatibility playback...',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Check FFmpeg again',
                    onPressed: server.refreshMediaCapability,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
              if (server.ffmpegAvailable == false)
                SelectableText(
                  'Expected: ${server.ffmpegExecutable}',
                  style: theme.textTheme.bodySmall,
                ),
              if (server.pairing.devices.isNotEmpty) ...[
                const Divider(height: 28),
                Text('Paired TVs', style: theme.textTheme.labelLarge),
                const SizedBox(height: 6),
                for (final device in server.pairing.devices)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(Icons.tv_rounded),
                    title: Text(device.name),
                    subtitle: Text(
                      'Paired ${_dateLabel(device.pairedAt)} | '
                      'last seen ${_dateTimeLabel(device.lastSeenAt)}',
                    ),
                    trailing: IconButton(
                      tooltip: 'Remove TV',
                      onPressed: () => server.revokeDevice(device.id),
                      icon: const Icon(Icons.link_off_rounded),
                    ),
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

String _dateLabel(DateTime value) {
  final local = value.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}

String _dateTimeLabel(DateTime value) {
  final local = value.toLocal();
  return '${_dateLabel(local)} '
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}
