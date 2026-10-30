import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jewellery_suite/ui/widgets.dart';

/// #06D: “Hold and drag here to delete” did nothing, because the pawn tile's
/// own `InkWell.onLongPress` won the gesture arena and the tile was never
/// lifted. These tests lock the contract of [DragToDeleteTile]:
///
/// * hold + move + drop on the bin  -> the payload's drop runs,
/// * hold + release in place        -> the tile's own long-press menu runs,
/// * and neither path fires both.
void main() {
  late int dropped;
  late int menuOpened;
  late bool trashed;

  Future<void> pumpTiles(WidgetTester tester) async {
    dropped = 0;
    menuOpened = 0;
    trashed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => Stack(
              children: [
                Center(
                  child: DragToDeleteTile(
                    onDragChanged: (v) => setState(() => trashed = v),
                    onLongPress: () => menuOpened++,
                    payload: DeletePayload(
                      drop: () async {
                        dropped++;
                        return true;
                      },
                    ),
                    child: const SizedBox(
                      width: 220,
                      height: 64,
                      child: Center(child: Text('TILE')),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: DeleteTrashTarget(
                    visible: trashed,
                    onDrop: (p) async {
                      setState(() => trashed = false);
                      return p.drop();
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('hold, move and drop on the bin runs the delete', (tester) async {
    await pumpTiles(tester);

    final gesture =
        await tester.startGesture(tester.getCenter(find.text('TILE')));
    // Long-press delay, then a real move so the tile counts as dragged.
    await tester.pump(const Duration(seconds: 1));
    expect(trashed, isTrue, reason: 'the bin must appear once the drag starts');
    // Let the bin finish sliding in: while it is still translated down its
    // DragTarget is not where it looks, so a fast drop can miss it.
    await tester.pump(const Duration(milliseconds: 250));

    await gesture.moveTo(const Offset(400, 560));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(dropped, 1);
    expect(menuOpened, 0, reason: 'a real drag is not a long-press menu');
  });

  testWidgets('hold and release in place opens the tile menu instead',
      (tester) async {
    await pumpTiles(tester);    // The drag feedback is a second copy of the tile, so the start point is
    // read before the gesture begins.
    final start = tester.getCenter(find.text('TILE'));
    final gesture = await tester.startGesture(start);
    await tester.pump(const Duration(seconds: 1));
    // A couple of pixels of jitter must not be mistaken for a drag.
    await gesture.moveTo(start + const Offset(2, 2));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(menuOpened, 1);
    expect(dropped, 0, reason: 'releasing in place must never delete');
  });
}
