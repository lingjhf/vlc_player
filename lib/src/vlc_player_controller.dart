import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'vlc_player_value.dart';

class VlcPlayerController extends ValueNotifier<VlcPlayerValue> {
  VlcPlayerController({
    Uri? source,
    this.autoPlay = false,
    this.options = const <String>[],
    this.httpHeaders = const <String, String>{},
  }) : super(const VlcPlayerValue()) {
    _pendingSource = source;
    _pendingAutoPlay = autoPlay;
    _pendingHttpHeaders = httpHeaders;
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
    await _eventsSubscription?.cancel();
    _eventsSubscription = null;
    if (oldViewId != null) {
      await _disposeNativeView(oldViewId);
    }

    _viewId = viewId;
    _textureId = null;
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
    }
  }

  @internal
  Future<int> attachTextureForWindows() async {
    _ensureNotDisposed();

    final existingTextureId = _textureId;
    if (_viewId != null && existingTextureId != null) {
      return existingTextureId;
    }

    final oldViewId = _viewId;
    await _eventsSubscription?.cancel();
    _eventsSubscription = null;
    if (oldViewId != null) {
      await _disposeNativeView(oldViewId);
    }

    final response = await methodChannel.invokeMapMethod<String, Object?>(
      'create',
      <String, Object?>{'options': options},
    );
    final viewId = (response?['viewId'] as num?)?.toInt();
    final textureId = (response?['textureId'] as num?)?.toInt();
    if (viewId == null || textureId == null) {
      throw StateError('Windows vlc_player creation returned invalid data.');
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
    _pendingSource = source;
    _pendingAutoPlay = autoPlay;
    _pendingHttpHeaders = Map<String, String>.unmodifiable(httpHeaders);

    final viewId = _viewId;
    if (viewId == null) {
      return;
    }

    await methodChannel.invokeMethod<void>('setSource', <String, Object?>{
      'viewId': viewId,
      'uri': source.toString(),
      'autoPlay': autoPlay,
      'httpHeaders': httpHeaders,
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
    if (speed <= 0) {
      throw ArgumentError.value(speed, 'speed', 'Must be greater than zero.');
    }
    return _invoke('setPlaybackSpeed', <String, Object?>{'speed': speed});
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
