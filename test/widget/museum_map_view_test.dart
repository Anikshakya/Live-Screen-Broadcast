import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirror/shared/museum_map_view.dart';
import 'package:mirror/shared/museum_poi.dart';

void main() {
  testWidgets('selecting a place shows details and reset clears selection', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MuseumMapView(pois: MuseumPoi.samplePois)),
      ),
    );

    await tester.tap(find.widgetWithText(ActionChip, 'ZOO'));
    await tester.pumpAndSettle();

    expect(find.text('Prehistoric Wildlife Zoo'), findsAtLeastNWidgets(1));
    expect(find.text('Read More'), findsOneWidget);

    await tester.tap(find.byTooltip('Reset Map View'));
    await tester.pumpAndSettle();

    expect(find.text('Prehistoric Wildlife Zoo'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
