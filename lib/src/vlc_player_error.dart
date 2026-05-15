import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

abstract final class VlcPlayerErrorCode {
  static const String invalidArgs = 'invalid_args';
  static const String playerNotFound = 'player_not_found';
  static const String createFailed = 'create_failed';
  static const String setSourceFailed = 'set_source_failed';
  static const String trackNotFound = 'track_not_found';
  static const String addSubtitleFailed = 'add_subtitle_failed';
  static const String playbackError = 'playback_error';
  static const String disposed = 'disposed';
  static const String eventChannelError = 'event_channel_error';
}

@immutable
class VlcPlayerError {
  const VlcPlayerError({required this.code, this.message, this.details});

  factory VlcPlayerError.fromMap(Map<Object?, Object?> map) {
    return VlcPlayerError(
      code: map['code'] as String? ?? VlcPlayerErrorCode.playbackError,
      message: map['message'] as String?,
      details: map['details'],
    );
  }

  factory VlcPlayerError.fromPlatformException(PlatformException error) {
    return VlcPlayerError(
      code: error.code,
      message: error.message,
      details: error.details,
    );
  }

  final String code;
  final String? message;
  final Object? details;

  String get description => message ?? code;

  @override
  bool operator ==(Object other) {
    return other is VlcPlayerError &&
        other.code == code &&
        other.message == message &&
        other.details == details;
  }

  @override
  int get hashCode => Object.hash(code, message, details);

  @override
  String toString() {
    final message = this.message;
    if (message == null || message.isEmpty) {
      return 'VlcPlayerError($code)';
    }
    return 'VlcPlayerError($code, $message)';
  }
}

class VlcPlayerException implements Exception {
  const VlcPlayerException(this.error);

  factory VlcPlayerException.fromPlatformException(PlatformException error) {
    return VlcPlayerException(VlcPlayerError.fromPlatformException(error));
  }

  final VlcPlayerError error;

  String get code => error.code;

  String? get message => error.message;

  Object? get details => error.details;

  @override
  String toString() => 'VlcPlayerException(${error.description})';
}
