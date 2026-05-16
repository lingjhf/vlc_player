import 'package:flutter_test/flutter_test.dart';
import 'package:vlc_player/vlc_player.dart';

import 'vlc_method_channel_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late VlcMethodChannelHarness harness;

  setUp(() {
    harness = VlcMethodChannelHarness()..install();
  });

  tearDown(() {
    harness.dispose();
  });

  test('repeated native events keep listener notifications bounded', () async {
    final controller = VlcPlayerController();
    harness.mockEventChannel(41);
    await controller.attach(41);

    var notifications = 0;
    controller.addListener(() {
      notifications += 1;
    });

    await harness.sendEvents(
      41,
      List<Map<String, Object?>>.generate(120, (index) {
        final position = (index ~/ 3) * 250;
        return <String, Object?>{
          'state': 'playing',
          'position': position,
          'duration': 30000,
          'volume': 100,
          'playbackSpeed': 1.0,
          'isReady': true,
          'isSeekable': true,
          'isLive': false,
          'videoSize': <String, Object?>{'width': 640, 'height': 360},
        };
      }),
    );

    expect(notifications, 40);

    controller.dispose();
  });

  test('event channel errors notify once for equivalent payloads', () async {
    final controller = VlcPlayerController();
    harness.mockEventChannel(42);
    await controller.attach(42);

    var notifications = 0;
    controller.addListener(() {
      notifications += 1;
    });

    await harness.sendError(
      42,
      code: VlcPlayerErrorCode.playbackError,
      message: 'Decoder failed.',
      details: const <String, Object?>{'codec': 'h264'},
    );
    await harness.sendError(
      42,
      code: VlcPlayerErrorCode.playbackError,
      message: 'Decoder failed.',
      details: const <String, Object?>{'codec': 'h264'},
    );

    expect(notifications, 1);
    expect(controller.value.hasError, isTrue);
    expect(controller.value.errorDescription, 'Decoder failed.');

    controller.dispose();
  });
}
