import 'package:another_iptv_player/models/player_aspect_ratio_mode.dart';
import 'package:another_iptv_player/widgets/player-buttons/video_aspect_ratio_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('commits selection after the source control is unmounted', (
    tester,
  ) async {
    var showButton = true;
    PlayerAspectRatioMode? selectedMode;
    final selectedModeNotifier = ValueNotifier(PlayerAspectRatioMode.original);
    addTearDown(selectedModeNotifier.dispose);
    late StateSetter rebuild;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return Scaffold(
              body: showButton
                  ? VideoAspectRatioWidget(
                      selectedModeListenable: selectedModeNotifier,
                      onChanged: (mode) {
                        selectedMode = mode;
                        selectedModeNotifier.value = mode;
                      },
                    )
                  : const SizedBox.shrink(),
            );
          },
        ),
      ),
    );

    await tester.tap(find.byTooltip('Aspect ratio'));
    await tester.pumpAndSettle();

    rebuild(() {
      showButton = false;
    });
    await tester.pump();

    expect(find.text('4:3'), findsOneWidget);
    await tester.tap(
      find.ancestor(
        of: find.text('4:3'),
        matching: find.byType(CheckedPopupMenuItem<PlayerAspectRatioMode>),
      ),
    );
    await tester.pumpAndSettle();

    expect(selectedMode, PlayerAspectRatioMode.ratio4x3);

    rebuild(() {
      showButton = true;
    });
    await tester.pump();
    await tester.tap(find.byTooltip('Aspect ratio'));
    await tester.pumpAndSettle();

    final selectedItem = tester
        .widget<CheckedPopupMenuItem<PlayerAspectRatioMode>>(
          find.ancestor(
            of: find.text('4:3'),
            matching: find.byType(CheckedPopupMenuItem<PlayerAspectRatioMode>),
          ),
        );
    expect(selectedItem.checked, isTrue);
  });
}
