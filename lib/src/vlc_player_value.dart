import 'package:flutter/foundation.dart';

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
    this.errorDescription,
  });

  final VlcPlaybackState state;
  final Duration position;
  final Duration duration;
  final int volume;
  final double playbackSpeed;
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
    String? errorDescription,
    bool clearError = false,
  }) {
    return VlcPlayerValue(
      state: state ?? this.state,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      volume: volume ?? this.volume,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
      errorDescription: clearError
          ? null
          : errorDescription ?? this.errorDescription,
    );
  }

  static VlcPlayerValue fromEvent(Object? event, VlcPlayerValue previous) {
    if (event is! Map) {
      return previous;
    }

    return previous.copyWith(
      state: _stateFromString(event['state'] as String?) ?? previous.state,
      position: _durationFromMilliseconds(event['position']),
      duration: _durationFromMilliseconds(event['duration']),
      volume: event['volume'] as int?,
      playbackSpeed: (event['playbackSpeed'] as num?)?.toDouble(),
      errorDescription: event['errorDescription'] as String?,
      clearError: event['errorDescription'] == null,
    );
  }

  static Duration? _durationFromMilliseconds(Object? value) {
    if (value is! num || value < 0) {
      return null;
    }
    return Duration(milliseconds: value.round());
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
