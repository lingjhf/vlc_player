import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';

import 'vlc_player_error.dart';

enum VlcPlaybackState {
  idle,
  opening,
  buffering,
  playing,
  paused,
  stopped,
  ended,
  error,
}

@immutable
class VlcPlayerValue {
  const VlcPlayerValue({
    this.state = VlcPlaybackState.idle,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.volume = 100,
    this.playbackSpeed = 1,
    this.isReady = false,
    this.isSeekable = false,
    this.isLive = false,
    this.videoSize,
    this.bufferingProgress,
    this.error,
    this.errorDescription,
  });

  final VlcPlaybackState state;
  final Duration position;
  final Duration duration;
  final int volume;
  final double playbackSpeed;
  final bool isReady;
  final bool isSeekable;
  final bool isLive;
  final Size? videoSize;
  final double? bufferingProgress;
  final VlcPlayerError? error;
  final String? errorDescription;

  bool get isPlaying => state == VlcPlaybackState.playing;

  bool get isBuffering => state == VlcPlaybackState.buffering;

  bool get hasError => state == VlcPlaybackState.error;

  VlcPlayerValue copyWith({
    VlcPlaybackState? state,
    Duration? position,
    Duration? duration,
    int? volume,
    double? playbackSpeed,
    bool? isReady,
    bool? isSeekable,
    bool? isLive,
    Size? videoSize,
    bool clearVideoSize = false,
    double? bufferingProgress,
    bool clearBufferingProgress = false,
    VlcPlayerError? error,
    String? errorDescription,
    bool clearError = false,
  }) {
    final nextError = clearError
        ? null
        : error ??
              (errorDescription == null
                  ? this.error
                  : VlcPlayerError(
                      code: VlcPlayerErrorCode.playbackError,
                      message: errorDescription,
                    ));
    final nextErrorDescription = clearError
        ? null
        : error != null
        ? error.message
        : errorDescription ?? this.errorDescription;
    return VlcPlayerValue(
      state: state ?? this.state,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      volume: volume ?? this.volume,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
      isReady: isReady ?? this.isReady,
      isSeekable: isSeekable ?? this.isSeekable,
      isLive: isLive ?? this.isLive,
      videoSize: clearVideoSize ? null : videoSize ?? this.videoSize,
      bufferingProgress: clearBufferingProgress
          ? null
          : bufferingProgress ?? this.bufferingProgress,
      error: nextError,
      errorDescription: nextErrorDescription,
    );
  }

  static VlcPlayerValue fromEvent(Object? event, VlcPlayerValue previous) {
    if (event is! Map) {
      return previous;
    }

    final state = _stateFromString(event['state'] as String?) ?? previous.state;
    final hasVideoSize = event.containsKey('videoSize');
    final videoSize = hasVideoSize ? _sizeFromMap(event['videoSize']) : null;
    final hasBufferingProgress = event.containsKey('bufferingProgress');
    final bufferingProgress = hasBufferingProgress
        ? _normalizedProgress(event['bufferingProgress'])
        : null;
    final error = _errorFromEvent(event);

    return previous.copyWith(
      state: state,
      position: _durationFromMilliseconds(event['position']),
      duration: _durationFromMilliseconds(event['duration']),
      volume: event['volume'] as int?,
      playbackSpeed: (event['playbackSpeed'] as num?)?.toDouble(),
      isReady: event['isReady'] as bool? ?? _isReadyState(state),
      isSeekable: event['isSeekable'] as bool?,
      isLive: event['isLive'] as bool?,
      videoSize: videoSize,
      clearVideoSize:
          (hasVideoSize && videoSize == null) || _clearsVideoSize(state),
      bufferingProgress: bufferingProgress,
      clearBufferingProgress:
          (hasBufferingProgress && bufferingProgress == null) ||
          state != VlcPlaybackState.buffering,
      error: error,
      errorDescription: error?.message,
      clearError: error == null,
    );
  }

  static Duration? _durationFromMilliseconds(Object? value) {
    if (value is! num || value < 0) {
      return null;
    }
    return Duration(milliseconds: value.round());
  }

  static Size? _sizeFromMap(Object? value) {
    if (value is! Map) {
      return null;
    }
    final width = (value['width'] as num?)?.toDouble();
    final height = (value['height'] as num?)?.toDouble();
    if (width == null || height == null || width <= 0 || height <= 0) {
      return null;
    }
    return Size(width, height);
  }

  static double? _normalizedProgress(Object? value) {
    if (value is! num || !value.isFinite) {
      return null;
    }
    return value.toDouble().clamp(0.0, 1.0).toDouble();
  }

  static VlcPlayerError? _errorFromEvent(Map<Object?, Object?> event) {
    final rawError = event['error'];
    if (rawError is Map) {
      return VlcPlayerError.fromMap(rawError.cast<Object?, Object?>());
    }

    final code = event['errorCode'] as String?;
    final description = event['errorDescription'] as String?;
    if (code == null && description == null) {
      return null;
    }
    return VlcPlayerError(
      code: code ?? VlcPlayerErrorCode.playbackError,
      message: description,
      details: event['errorDetails'],
    );
  }

  static bool _isReadyState(VlcPlaybackState state) {
    return switch (state) {
      VlcPlaybackState.playing ||
      VlcPlaybackState.paused ||
      VlcPlaybackState.stopped ||
      VlcPlaybackState.ended => true,
      _ => false,
    };
  }

  static bool _clearsVideoSize(VlcPlaybackState state) {
    return switch (state) {
      VlcPlaybackState.idle ||
      VlcPlaybackState.opening ||
      VlcPlaybackState.error => true,
      _ => false,
    };
  }

  static VlcPlaybackState? _stateFromString(String? value) {
    return switch (value) {
      'idle' => VlcPlaybackState.idle,
      'opening' => VlcPlaybackState.opening,
      'buffering' => VlcPlaybackState.buffering,
      'playing' => VlcPlaybackState.playing,
      'paused' => VlcPlaybackState.paused,
      'stopped' => VlcPlaybackState.stopped,
      'ended' => VlcPlaybackState.ended,
      'error' => VlcPlaybackState.error,
      _ => null,
    };
  }
}
