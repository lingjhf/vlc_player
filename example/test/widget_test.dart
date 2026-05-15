import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vlc_player_example/main.dart';

void main() {
  testWidgets('example app renders without a platform view', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp(showPlayer: false));

    expect(find.text('vlc_player example'), findsOneWidget);
    expect(find.text('Video file'), findsOneWidget);
    expect(find.text('HLS stream'), findsOneWidget);
    expect(find.text('Full player'), findsOneWidget);

    await tester.tap(find.text('Video file'));
    await tester.pumpAndSettle();
    expect(find.text('MP4 sample video'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('HLS stream'));
    await tester.pumpAndSettle();
    expect(find.text('M3U8 sample stream'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Full player'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    expect(find.byIcon(Icons.stay_current_landscape), findsOneWidget);
  });
}
