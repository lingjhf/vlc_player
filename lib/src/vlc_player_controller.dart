import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'vlc_media_info.dart';
import 'vlc_media_source.dart';
import 'vlc_player_error.dart';
import 'vlc_player_value.dart';

/// Playlist repeat behavior used by `VlcPlayerController.setPlaylist`.
enum VlcPlaylistLoopMode {
  /// Stop at the beginning or end of the playlist.
  none,

  /// Repeat the current playlist item when it ends.
  loopOne,

  /// Wrap to the first or last item when advancing past an edge.
  loopAll,
}

/// Controls a `VlcPlayer` and exposes playback state.
///
/// A controller can be configured before it is attached to a widget. Calls to
/// [setSource], [setMedia], or [setPlaylist] are remembered and applied when the
/// native player is created. Playback commands such as [play] and [pause]
/// require the controller to be attached to a `VlcPlayer`.
class VlcPlayerController extends ValueNotifier<VlcPlayerValue> {
  /// Creates a controller.
  ///
  /// Use [source] for a simple initial URI, or [mediaSource] when the initial
  /// item needs headers, media options, or a start position. Passing both
  /// [source] and [mediaSource] throws an [ArgumentError].
  VlcPlayerController({
    Uri? source,
    VlcMediaSource? mediaSource,
    this.autoPlay = false,
    List<String> options = const <String>[],
    Map<String, String> httpHeaders = const <String, String>{},
    this.eventThrottleInterval,
  }) : options = List<String>.unmodifiable(options),
       httpHeaders = Map<String, String>.unmodifiable(
         mediaSource?.httpHeaders ?? httpHeaders,
       ),
       super(const VlcPlayerValue()) {
    if (source != null && mediaSource != null) {
      throw ArgumentError(
        'Use either source or mediaSource, not both.',
        'mediaSource',
      );
    }
    if (eventThrottleInterval case final interval? when interval.isNegative) {
      throw ArgumentError.value(
        eventThrottleInterval,
        'eventThrottleInterval',
        'Must not be negative.',
      );
    }
    _pendingMediaSource =
        mediaSource ??
        (source == null
            ? null
            : VlcMediaSource(uri: source, httpHeaders: httpHeaders));
    _pendingAutoPlay = autoPlay;
  }

  /// Native platform view type used by the plugin.
  static const String viewType = 'plugins.lingjhf.com/vlc_player/view';

  /// Shared method channel used by tests and native command dispatch.
  @visibleForTesting
  static const MethodChannel methodChannel = MethodChannel('vlc_player');

  /// Whether the initially configured source should start playback immediately.
  final bool autoPlay;

  /// VLC instance options applied when the native player is created.
  final List<String> options;

  /// HTTP headers used when `source` is supplied to the constructor.
  final Map<String, String> httpHeaders;

  /// Optional interval used to coalesce progress-only native events.
  ///
  /// When set to a positive duration, updates that only change playback
  /// position, media duration, or buffering progress are delivered at most once
  /// per interval. State, readiness, track metadata, volume, speed, and errors
  /// still notify listeners immediately. The default `null` keeps every
  /// distinct native value update visible immediately.
  final Duration? eventThrottleInterval;

  int? _viewId;
  int? _textureId;
  VlcMediaSource? _pendingMediaSource;
  bool _pendingAutoPlay = false;
  List<VlcMediaSource> _playlist = const <VlcMediaSource>[];
  int? _playlistIndex;
  bool _playlistAutoAdvance = false;
  VlcPlaylistLoopMode _playlistLoopMode = VlcPlaylistLoopMode.none;
  StreamSubscription<Object?>? _eventsSubscription;
  Timer? _eventThrottleTimer;
  VlcPlayerValue? _pendingThrottledValue;
  bool _isDisposed = false;

  /// Whether this controller is currently attached to a native player instance.
  bool get isAttached => _viewId != null;

  /// Current playlist items, or an empty list when no playlist is active.
  List<VlcMediaSource> get playlist => _playlist;

  /// Current playlist index, or `null` when no playlist is active.
  int? get playlistIndex => _playlistIndex;

  /// Current playlist loop mode.
  VlcPlaylistLoopMode get playlistLoopMode => _playlistLoopMode;

  /// Current media source, including a pending source set before attachment.
  VlcMediaSource? get currentMediaSource => _pendingMediaSource;

  /// Whether [next] can move to another item without wrapping.
  bool get hasNext => switch (_playlistIndex) {
    final int index => index + 1 < _playlist.length,
    null => false,
  };

  /// Whether [previous] can move to another item without wrapping.
  bool get hasPrevious => switch (_playlistIndex) {
    final int index => index > 0,
    null => false,
  };

  /// Attaches this controller to a platform-view player instance.
  Future<void> attach(int viewId) async {
    _ensureNotDisposed();
    if (_viewId == viewId) {
      return;
    }

    final oldViewId = _viewId;
    _viewId = null;
    _textureId = null;
    await _eventsSubscription?.cancel();
    _eventsSubscription = null;
    _cancelPendingThrottledValue();
    if (oldViewId != null) {
      await _disposeNativeView(oldViewId);
    }
    if (_isDisposed) {
      await _disposeNativeView(viewId);
      throw StateError('The controller has been disposed.');
    }

    _viewId = viewId;
    _eventsSubscription = EventChannel(
      'vlc_player/events/$viewId',
    ).receiveBroadcastStream().listen(_handleEvent, onError: _handleEventError);

    final pendingMediaSource = _pendingMediaSource;
    if (pendingMediaSource != null) {
      await _setMedia(pendingMediaSource, autoPlay: _pendingAutoPlay);
      _ensureNotDisposed();
    }
  }

  /// Attaches this controller to a Windows texture-backed player instance.
  @internal
  Future<int> attachTextureForWindows() async {
    return attachTexturePlayer();
  }

  /// Attaches this controller to a texture-backed player instance.
  @internal
  Future<int> attachTexturePlayer() async {
    _ensureNotDisposed();

    final existingTextureId = _textureId;
    if (_viewId != null && existingTextureId != null) {
      return existingTextureId;
    }

    final oldViewId = _viewId;
    _viewId = null;
    _textureId = null;
    await _eventsSubscription?.cancel();
    _eventsSubscription = null;
    _cancelPendingThrottledValue();
    if (oldViewId != null) {
      await _disposeNativeView(oldViewId);
    }
    _ensureNotDisposed();

    final response = await _invokeNativeMap('create', <String, Object?>{
      'options': options,
    });
    final viewId = (response?['viewId'] as num?)?.toInt();
    final textureId = (response?['textureId'] as num?)?.toInt();
    if (viewId == null || textureId == null) {
      throw StateError('vlc_player texture creation returned invalid data.');
    }
    if (_isDisposed) {
      await _disposeNativeView(viewId);
      throw StateError('The controller has been disposed.');
    }

    _viewId = viewId;
    _textureId = textureId;
    _eventsSubscription = EventChannel(
      'vlc_player/events/$viewId',
    ).receiveBroadcastStream().listen(_handleEvent, onError: _handleEventError);

    final pendingMediaSource = _pendingMediaSource;
    if (pendingMediaSource != null) {
      await _setMedia(pendingMediaSource, autoPlay: _pendingAutoPlay);
      _ensureNotDisposed();
    }

    return textureId;
  }

  /// Detaches and disposes the native player instance, if one is attached.
  @internal
  Future<void> detach() async {
    final viewId = _viewId;
    _viewId = null;
    _textureId = null;
    await _eventsSubscription?.cancel();
    _eventsSubscription = null;
    _cancelPendingThrottledValue();
    if (viewId != null) {
      await _disposeNativeView(viewId);
    }
  }

  /// Loads a new media URI.
  ///
  /// This clears any active playlist. The command can be called before the
  /// controller is attached; the source is applied when `VlcPlayer` creates the
  /// native player.
  Future<void> setSource(
    Uri source, {
    bool autoPlay = false,
    Map<String, String> httpHeaders = const <String, String>{},
  }) async {
    return setMedia(
      VlcMediaSource(uri: source, httpHeaders: httpHeaders),
      autoPlay: autoPlay,
    );
  }

  /// Loads a [VlcMediaSource].
  ///
  /// Use this when the item needs HTTP headers, VLC media options, or an
  /// initial seek position. This clears any active playlist.
  Future<void> setMedia(VlcMediaSource source, {bool autoPlay = false}) async {
    _ensureNotDisposed();
    final previousPlaylist = _playlist;
    final previousPlaylistIndex = _playlistIndex;
    final previousPlaylistAutoAdvance = _playlistAutoAdvance;
    final previousPlaylistLoopMode = _playlistLoopMode;
    final previousMediaSource = _pendingMediaSource;
    final previousAutoPlay = _pendingAutoPlay;
    _clearPlaylist();
    try {
      await _setMedia(source, autoPlay: autoPlay);
    } catch (_) {
      _playlist = previousPlaylist;
      _playlistIndex = previousPlaylistIndex;
      _playlistAutoAdvance = previousPlaylistAutoAdvance;
      _playlistLoopMode = previousPlaylistLoopMode;
      _pendingMediaSource = previousMediaSource;
      _pendingAutoPlay = previousAutoPlay;
      rethrow;
    }
  }

  /// Loads a playlist and selects [initialIndex].
  ///
  /// [sources] must be non-empty. When [autoAdvance] is true, the controller
  /// advances after VLC reports that the current item ended. [loopMode] controls
  /// repeat and wrap behavior.
  Future<void> setPlaylist(
    List<VlcMediaSource> sources, {
    int initialIndex = 0,
    bool autoPlay = false,
    bool autoAdvance = true,
    VlcPlaylistLoopMode loopMode = VlcPlaylistLoopMode.none,
  }) async {
    _ensureNotDisposed();
    if (sources.isEmpty) {
      throw ArgumentError.value(sources, 'sources', 'Must be non-empty.');
    }
    RangeError.checkValidIndex(initialIndex, sources, 'initialIndex');

    final previousPlaylist = _playlist;
    final previousPlaylistIndex = _playlistIndex;
    final previousPlaylistAutoAdvance = _playlistAutoAdvance;
    final previousPlaylistLoopMode = _playlistLoopMode;
    final previousMediaSource = _pendingMediaSource;
    final previousAutoPlay = _pendingAutoPlay;
    _playlist = List<VlcMediaSource>.unmodifiable(sources);
    _playlistIndex = initialIndex;
    _playlistAutoAdvance = autoAdvance;
    _playlistLoopMode = loopMode;
    try {
      await _setMedia(_playlist[initialIndex], autoPlay: autoPlay);
    } catch (_) {
      _playlist = previousPlaylist;
      _playlistIndex = previousPlaylistIndex;
      _playlistAutoAdvance = previousPlaylistAutoAdvance;
      _playlistLoopMode = previousPlaylistLoopMode;
      _pendingMediaSource = previousMediaSource;
      _pendingAutoPlay = previousAutoPlay;
      rethrow;
    }
  }

  /// Moves to the next playlist item.
  ///
  /// Returns `false` when there is no next item and [playlistLoopMode] is
  /// [VlcPlaylistLoopMode.none]. Throws [StateError] when no playlist is active.
  Future<bool> next({bool autoPlay = true}) {
    return _moveInPlaylist(1, autoPlay: autoPlay);
  }

  /// Moves to the previous playlist item.
  ///
  /// Returns `false` when there is no previous item and [playlistLoopMode] is
  /// [VlcPlaylistLoopMode.none]. Throws [StateError] when no playlist is active.
  Future<bool> previous({bool autoPlay = true}) {
    return _moveInPlaylist(-1, autoPlay: autoPlay);
  }

  Future<bool> _moveInPlaylist(int delta, {required bool autoPlay}) async {
    _ensureNotDisposed();
    final index = _playlistIndex;
    if (index == null) {
      throw StateError('No playlist has been set.');
    }

    final nextIndex = index + delta;
    if (nextIndex < 0 || nextIndex >= _playlist.length) {
      if (_playlistLoopMode != VlcPlaylistLoopMode.loopAll) {
        return false;
      }
      return _loadPlaylistIndex(
        nextIndex < 0 ? _playlist.length - 1 : 0,
        autoPlay: autoPlay,
      );
    }

    return _loadPlaylistIndex(nextIndex, autoPlay: autoPlay);
  }

  Future<bool> _loadPlaylistIndex(
    int nextIndex, {
    required bool autoPlay,
  }) async {
    final index = _playlistIndex;
    if (index == null) {
      throw StateError('No playlist has been set.');
    }

    _playlistIndex = nextIndex;
    final previousMediaSource = _pendingMediaSource;
    final previousAutoPlay = _pendingAutoPlay;
    try {
      await _setMedia(_playlist[nextIndex], autoPlay: autoPlay);
    } catch (_) {
      _playlistIndex = index;
      _pendingMediaSource = previousMediaSource;
      _pendingAutoPlay = previousAutoPlay;
      rethrow;
    }
    return true;
  }

  Future<void> _setMedia(
    VlcMediaSource source, {
    required bool autoPlay,
  }) async {
    _ensureNotDisposed();
    _pendingMediaSource = source;
    _pendingAutoPlay = autoPlay;

    final viewId = _viewId;
    if (viewId == null) {
      return;
    }

    await _invokeNative<void>('setSource', <String, Object?>{
      'viewId': viewId,
      'uri': source.uri.toString(),
      'autoPlay': autoPlay,
      'httpHeaders': source.httpHeaders,
      if (source.mediaOptions.isNotEmpty) 'mediaOptions': source.mediaOptions,
      if (source.startPosition > Duration.zero)
        'startPosition': source.startPosition.inMilliseconds,
    });
  }

  void _clearPlaylist() {
    _playlist = const <VlcMediaSource>[];
    _playlistIndex = null;
    _playlistAutoAdvance = false;
    _playlistLoopMode = VlcPlaylistLoopMode.none;
  }

  /// Starts or resumes playback.
  Future<void> play() => _invoke('play');

  /// Pauses playback.
  Future<void> pause() => _invoke('pause');

  /// Stops playback.
  Future<void> stop() => _invoke('stop');

  /// Seeks to [position].
  ///
  /// [position] must be non-negative.
  Future<void> seekTo(Duration position) {
    if (position.isNegative) {
      throw ArgumentError.value(position, 'position', 'Must be non-negative.');
    }
    return _invoke('seekTo', <String, Object?>{
      'position': position.inMilliseconds,
    });
  }

  /// Sets VLC volume.
  ///
  /// Values are clamped to VLC's `0..200` range.
  Future<void> setVolume(int volume) {
    return _invoke('setVolume', <String, Object?>{
      'volume': volume.clamp(0, 200),
    });
  }

  /// Sets playback speed.
  ///
  /// [speed] must be finite and greater than zero. `1.0` is normal speed.
  Future<void> setPlaybackSpeed(double speed) {
    if (!speed.isFinite || speed <= 0) {
      throw ArgumentError.value(
        speed,
        'speed',
        'Must be finite and greater than zero.',
      );
    }
    return _invoke('setPlaybackSpeed', <String, Object?>{'speed': speed});
  }

  /// Returns selectable audio tracks for the current media.
  Future<List<VlcTrackDescription>> getAudioTracks() async {
    final tracks = await _invokeFor<List<Object?>>('getAudioTracks');
    return _trackDescriptionsFrom(tracks);
  }

  /// Selects an audio track by VLC track [id].
  ///
  /// Use an id returned by [getAudioTracks].
  Future<void> setAudioTrack(int id) {
    if (id < 0) {
      throw ArgumentError.value(id, 'id', 'Must be non-negative.');
    }
    return _invoke('setAudioTrack', <String, Object?>{'id': id});
  }

  /// Returns selectable embedded subtitle tracks for the current media.
  Future<List<VlcTrackDescription>> getSubtitleTracks() async {
    final tracks = await _invokeFor<List<Object?>>('getSubtitleTracks');
    return _trackDescriptionsFrom(tracks);
  }

  /// Selects an embedded subtitle track by VLC track [id].
  ///
  /// Use an id returned by [getSubtitleTracks].
  Future<void> setSubtitleTrack(int id) {
    if (id < 0) {
      throw ArgumentError.value(id, 'id', 'Must be non-negative.');
    }
    return _invoke('setSubtitleTrack', <String, Object?>{'id': id});
  }

  /// Disables subtitle rendering for the current media.
  Future<void> disableSubtitle() => _invoke('disableSubtitle');

  /// Adds and selects an external subtitle from [uri].
  ///
  /// [uri] can point to a local file or a remote subtitle URL supported by VLC.
  Future<void> addSubtitle(Uri uri) {
    final value = uri.toString();
    if (value.isEmpty) {
      throw ArgumentError.value(uri, 'uri', 'Must be non-empty.');
    }
    return _invoke('addSubtitle', <String, Object?>{'uri': value});
  }

  /// Returns metadata and discovered track details for the current media.
  Future<VlcMediaInfo> getMediaInfo() async {
    final info = await _invokeFor<Map<Object?, Object?>>('getMediaInfo');
    return VlcMediaInfo.fromMap(info ?? const <Object?, Object?>{});
  }

  Future<void> _invoke(String method, [Map<String, Object?>? arguments]) {
    _ensureNotDisposed();
    final viewId = _viewId;
    if (viewId == null) {
      throw StateError('The controller is not attached to a VlcPlayer.');
    }

    return _invokeNative<void>(method, <String, Object?>{
      'viewId': viewId,
      if (arguments != null) ...arguments,
    });
  }

  Future<T?> _invokeFor<T>(String method, [Map<String, Object?>? arguments]) {
    _ensureNotDisposed();
    final viewId = _viewId;
    if (viewId == null) {
      throw StateError('The controller is not attached to a VlcPlayer.');
    }

    return _invokeNative<T>(method, <String, Object?>{
      'viewId': viewId,
      if (arguments != null) ...arguments,
    });
  }

  Future<T?> _invokeNative<T>(
    String method,
    Map<String, Object?> arguments,
  ) async {
    try {
      return await methodChannel.invokeMethod<T>(method, arguments);
    } on PlatformException catch (error, stackTrace) {
      Error.throwWithStackTrace(
        VlcPlayerException.fromPlatformException(error),
        stackTrace,
      );
    }
  }

  Future<Map<String, Object?>?> _invokeNativeMap(
    String method,
    Map<String, Object?> arguments,
  ) async {
    try {
      return await methodChannel.invokeMapMethod<String, Object?>(
        method,
        arguments,
      );
    } on PlatformException catch (error, stackTrace) {
      Error.throwWithStackTrace(
        VlcPlayerException.fromPlatformException(error),
        stackTrace,
      );
    }
  }

  static List<VlcTrackDescription> _trackDescriptionsFrom(Object? value) {
    if (value is! Iterable) {
      return const <VlcTrackDescription>[];
    }
    return value
        .whereType<Map>()
        .map(
          (track) =>
              VlcTrackDescription.fromMap(track.cast<Object?, Object?>()),
        )
        .toList(growable: false);
  }

  Future<void> _disposeNativeView(int viewId) {
    return methodChannel.invokeMethod<void>('dispose', <String, Object?>{
      'viewId': viewId,
    });
  }

  void _handleEvent(Object? event) {
    if (_isDisposed) {
      return;
    }
    final previousValue = _pendingThrottledValue ?? value;
    final nextValue = VlcPlayerValue.fromEvent(event, previousValue);
    _setValueFromEvent(previousValue, nextValue);
    if (_playlistAutoAdvance &&
        previousValue.state != VlcPlaybackState.ended &&
        nextValue.state == VlcPlaybackState.ended) {
      if (_playlistLoopMode == VlcPlaylistLoopMode.loopOne) {
        final current = _pendingMediaSource;
        if (current != null) {
          _runAutoAdvance(_setMedia(current, autoPlay: true));
        }
      } else if (hasNext || _playlistLoopMode == VlcPlaylistLoopMode.loopAll) {
        _runAutoAdvance(next().then<void>((_) {}));
      }
    }
  }

  void _runAutoAdvance(Future<void> operation) {
    unawaited(
      operation.catchError((Object error, StackTrace stackTrace) {
        _handleAutoAdvanceError(error);
      }),
    );
  }

  void _handleAutoAdvanceError(Object error) {
    if (_isDisposed) {
      return;
    }
    final playerError = error is VlcPlayerException
        ? error.error
        : error is PlatformException
        ? VlcPlayerError.fromPlatformException(error)
        : VlcPlayerError(
            code: VlcPlayerErrorCode.playbackError,
            message: error.toString(),
          );
    _setPlayerError(playerError);
  }

  void _handleEventError(Object error) {
    if (_isDisposed) {
      return;
    }
    final playerError = error is PlatformException
        ? VlcPlayerError.fromPlatformException(error)
        : VlcPlayerError(
            code: VlcPlayerErrorCode.eventChannelError,
            message: error.toString(),
          );
    _setPlayerError(playerError);
  }

  void _setPlayerError(VlcPlayerError playerError) {
    _cancelPendingThrottledValue();
    value = value.copyWith(
      state: VlcPlaybackState.error,
      error: playerError,
      errorDescription: playerError.message,
    );
  }

  void _setValueFromEvent(
    VlcPlayerValue previousValue,
    VlcPlayerValue nextValue,
  ) {
    if (nextValue == previousValue) {
      return;
    }
    if (!_shouldThrottleEvent(previousValue, nextValue)) {
      _setValueImmediately(nextValue);
      return;
    }
    _pendingThrottledValue = nextValue;
    _eventThrottleTimer ??= Timer(eventThrottleInterval!, _flushThrottledValue);
  }

  bool _shouldThrottleEvent(
    VlcPlayerValue previousValue,
    VlcPlayerValue nextValue,
  ) {
    final interval = eventThrottleInterval;
    if (interval == null || interval.inMicroseconds == 0) {
      return false;
    }
    return previousValue.state == nextValue.state &&
        previousValue.volume == nextValue.volume &&
        previousValue.playbackSpeed == nextValue.playbackSpeed &&
        previousValue.isReady == nextValue.isReady &&
        previousValue.isSeekable == nextValue.isSeekable &&
        previousValue.isLive == nextValue.isLive &&
        previousValue.videoSize == nextValue.videoSize &&
        previousValue.error == nextValue.error &&
        previousValue.errorDescription == nextValue.errorDescription;
  }

  void _setValueImmediately(VlcPlayerValue nextValue) {
    _cancelPendingThrottledValue();
    value = nextValue;
  }

  void _flushThrottledValue() {
    final pendingValue = _pendingThrottledValue;
    _eventThrottleTimer = null;
    _pendingThrottledValue = null;
    if (!_isDisposed && pendingValue != null) {
      value = pendingValue;
    }
  }

  void _cancelPendingThrottledValue() {
    _eventThrottleTimer?.cancel();
    _eventThrottleTimer = null;
    _pendingThrottledValue = null;
  }

  void _ensureNotDisposed() {
    if (_isDisposed) {
      throw StateError('The controller has been disposed.');
    }
  }

  /// Disposes the controller and releases the attached native player.
  @override
  void dispose() {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    final viewId = _viewId;
    _viewId = null;
    _textureId = null;
    _eventsSubscription?.cancel();
    _eventsSubscription = null;
    _cancelPendingThrottledValue();
    if (viewId != null) {
      unawaited(_disposeNativeView(viewId));
    }
    super.dispose();
  }
}
