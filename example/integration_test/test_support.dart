import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pumpNavigation(WidgetTester tester) async {
  await tester.pump();
  await tester.pumpAndSettle(
    const Duration(milliseconds: 50),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 10),
  );
}

Future<void> openExampleTile(WidgetTester tester, String key) async {
  final tile = find.byKey(ValueKey<String>(key));
  await tester.ensureVisible(tile);
  await pumpNavigation(tester);
  await tester.tap(tile);
  await pumpNavigation(tester);
}

Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  int attempts = 40,
  Duration interval = const Duration(milliseconds: 250),
}) async {
  for (var attempt = 0; attempt < attempts && !condition(); attempt += 1) {
    await tester.pump(interval);
  }
}

Future<void> popRoute(WidgetTester tester, Finder routeContent) async {
  Navigator.of(tester.element(routeContent)).pop();
  await pumpNavigation(tester);
}

List<String> headlessPlayerOptions({bool requiresAudio = false}) {
  if (Platform.isLinux || requiresAudio) {
    return const <String>['--aout=dummy'];
  }
  return const <String>['--no-audio'];
}

Future<Uri> materializeAsset(String assetPath) async {
  final directory = await Directory.systemTemp.createTemp(
    'vlc_player_format_fixture_',
  );
  final file = File(
    '${directory.path}${Platform.pathSeparator}${assetPath.split('/').last}',
  );
  await _writeAsset(assetPath, file);
  return file.uri;
}

Future<Uri> materializeHlsFixture({
  required String playlistAssetPath,
  required String segmentAssetPath,
}) async {
  final directory = await Directory.systemTemp.createTemp(
    'vlc_player_hls_fixture_',
  );
  final segment = File('${directory.path}${Platform.pathSeparator}segment.ts');
  final playlist = File(
    '${directory.path}${Platform.pathSeparator}playlist.m3u8',
  );
  await _writeAsset(segmentAssetPath, segment);
  await _writeAsset(playlistAssetPath, playlist);
  return playlist.uri;
}

Future<void> _writeAsset(String assetPath, File file) async {
  final data = await rootBundle.load(assetPath);
  await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
}
