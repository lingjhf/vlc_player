import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vlc_player/vlc_player.dart';

void main() {
  group('VlcPlayerError', () {
    test('parses map payloads', () {
      final error = VlcPlayerError.fromMap(<Object?, Object?>{
        'code': 'track_not_found',
        'message': 'Missing track',
        'details': <String, Object?>{'id': 3},
      });

      expect(error.code, VlcPlayerErrorCode.trackNotFound);
      expect(error.message, 'Missing track');
      expect(error.details, <String, Object?>{'id': 3});
      expect(error.description, 'Missing track');
    });

    test('ignores malformed map code and message fields', () {
      final error = VlcPlayerError.fromMap(<Object?, Object?>{
        'code': 7,
        'message': Object(),
        'details': <String, Object?>{'raw': true},
      });

      expect(error.code, VlcPlayerErrorCode.playbackError);
      expect(error.message, isNull);
      expect(error.details, <String, Object?>{'raw': true});
      expect(error.description, VlcPlayerErrorCode.playbackError);
    });

    test('parses platform exceptions', () {
      final error = VlcPlayerError.fromPlatformException(
        PlatformException(
          code: VlcPlayerErrorCode.playerNotFound,
          message: 'No player',
          details: 7,
        ),
      );

      expect(error.code, VlcPlayerErrorCode.playerNotFound);
      expect(error.message, 'No player');
      expect(error.details, 7);
    });
  });

  group('VlcPlayerException', () {
    test('exposes code, message, and details', () {
      const exception = VlcPlayerException(
        VlcPlayerError(
          code: VlcPlayerErrorCode.invalidArgs,
          message: 'Invalid argument',
          details: 'speed',
        ),
      );

      expect(exception.code, VlcPlayerErrorCode.invalidArgs);
      expect(exception.message, 'Invalid argument');
      expect(exception.details, 'speed');
      expect(exception.toString(), contains('Invalid argument'));
    });
  });
}
