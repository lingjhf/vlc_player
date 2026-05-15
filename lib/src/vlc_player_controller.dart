import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'vlc_media_info.dart';
import 'vlc_player_value.dart';

class VlcPlayerController extends ValueNotifier<VlcPlayerValue> {
  VlcPlayerController({
    Uri? source,
    this.autoPlay = false,
    List<String> options = const <String>[],
    Map<String, String> httpHeaders = const <String, String>{},
  }) : options = List<String>.unmodifiable(options),
       httpHeaders = Map<String, String>.unmodifiable(httpHeaders),
       super(const VlcPlayerValue()) {
    if (source != null && source.toString().isEmpty) {
      throw ArgumentError.value(source, 'source', 'Must be non-empty.');
    }
    _pendingSource = source;
    _pendingAutoPlay = autoPlay;
    _pendingHttpHeaders = this.httpHeaders;
  }

  static const String viewType = 'plugins.lingjhf.com/vlc_player/view';

  @visibleForTesting
  static const MethodChannel methodChannel = MethodChannel('vlc_player');

  final bool autoPlay;
  final List<String> options;
  final Map<String, String> httpHeaders;

  int? _viewId;
  int? _textureId;
  Uri? _pendingSource;
  bool _pendingAutoPlay = false;
  Map<String, String> _pendingHttpHeaders = const <String, String>{};
  StreamSubscription<Object?>? _eventsSubscription;
  bool _isDisposed = false;

  bool get isAttached => _viewId != null;

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

    final pendingSource = _pendingSource;
    if (pendingSource != null) {
      await setSource(
        pendingSource,
        autoPlay: _pendingAutoPlay,
        httpHeaders: _pendingHttpHeaders,
      );
      _ensureNotDisposed();
    }
  }

  @internal
  Future<int> attachTextureForWindows() async {
    return attachTexturePlayer();
  }

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
    if (oldViewId != null) {
      await _disposeNativeView(oldViewId);
    }
    _ensureNotDisposed();

    final response = await methodChannel.invokeMapMethod<String, Object?>(
      'create',
      <String, Object?>{'options': options},
    );
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

    final pendingSource = _pendingSource;
    if (pendingSource != null) {
      await setSource(
        pendingSource,
        autoPlay: _pendingAutoPlay,
        httpHeaders: _pendingHttpHeaders,
      );
      _ensureNotDisposed();
    }

    return textureId;
  }

  @internal
  Future<void> detach() async {
    final viewId = _viewId;
    _viewId = null;
    _textureId = null;
    await _eventsSubscription?.cancel();
    _eventsSubscription = null;
    if (viewId != null) {
      await _disposeNativeView(viewId);
    }
  }

  Future<void> setSource(
    Uri source, {
    bool autoPlay = false,
    Map<String, String> httpHeaders = const <String, String>{},
  }) async {
    _ensureNotDisposed();
    final sourceValue = source.toString();
    if (sourceValue.isEmpty) {
      throw ArgumentError.value(source, 'source', 'Must be non-empty.');
    }
    _pendingSource = source;
    _pendingAutoPlay = autoPlay;
    _pendingHttpHeaders = Map<String, String>.unmodifiable(httpHeaders);

    final viewId = _viewId;
    if (viewId == null) {
      return;
    }

    await methodChannel.invokeMethod<void>('setSource', <String, Object?>{
      'viewId': viewId,
      'uri': sourceValue,
      'autoPlay': autoPlay,
      'httpHeaders': _pendingHttpHeaders,
    });
  }

  Future<void> play() => _invoke('play');

  Future<void> pause() => _invoke('pause');

  Future<void> stop() => _invoke('stop');

  Future<void> seekTo(Duration position) {
    if (position.isNegative) {
      throw ArgumentError.value(position, 'position', 'Must be non-negative.');
    }
    return _invoke('seekTo', <String, Object?>{
      'position': position.inMilliseconds,
    });
  }

  Future<void> setVolume(int volume) {
    return _invoke('setVolume', <String, Object?>{
      'volume': volume.clamp(0, 200),
    });
  }

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

  Future<List<VlcTrackDescription>> getAudioTracks() async {
    final tracks = await _invokeFor<List<Object?>>('getAudioTracks');
    return _trackDescriptionsFrom(tracks);
  }

  Future<void> setAudioTrack(int id) {
    if (id < 0) {
      throw ArgumentError.value(id, 'id', 'Must be non-negative.');
    }
    return _invoke('setAudioTrack', <String, Object?>{'id': id});
  }

  Future<List<VlcTrackDescription>> getSubtitleTracks() async {
    final tracks = await _invokeFor<List<Object?>>('getSubtitleTracks');
    return _trackDescriptionsFrom(tracks);
  }

  Future<void> setSubtitleTrack(int id) {
    if (id < 0) {
      throw ArgumentError.value(id, 'id', 'Must be non-negative.');
    }
    return _invoke('setSubtitleTrack', <String, Object?>{'id': id});
  }

  Future<void> disableSubtitle() => _invoke('disableSubtitle');

  Future<void> addSubtitle(Uri uri) {
    final value = uri.toString();
    if (value.isEmpty) {
      throw ArgumentError.value(uri, 'uri', 'Must be non-empty.');
    }
    return _invoke('addSubtitle', <String, Object?>{'uri': value});
  }

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

    return methodChannel.invokeMethod<void>(method, <String, Object?>{
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

    return methodChannel.invokeMethod<T>(method, <String, Object?>{
      'viewId': viewId,
      if (arguments != null) ...arguments,
    });
  }

  static List<VlcTrackDescription> _trackDescriptionsFrom(Object? value) {
    if (value is! List<Object?>) {
      return const <VlcTrackDescription>[];
    }
    return value
        .whereType<Map<Object?, Object?>>()
        .map(VlcTrackDescription.fromMap)
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
    value = VlcPlayerValue.fromEvent(event, value);
  }

  void _handleEventError(Object error) {
    if (_isDisposed) {
      return;
    }
    value = value.copyWith(
      state: VlcPlaybackState.error,
      errorDescription: error.toString(),
    );
  }

  void _ensureNotDisposed() {
    if (_isDisposed) {
      throw StateError('The controller has been disposed.');
    }
  }

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
    if (viewId != null) {
      unawaited(_disposeNativeView(viewId));
    }
    super.dispose();
  }
}
