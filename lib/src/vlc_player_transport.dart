import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'vlc_player_native_transport_stub.dart'
    if (dart.library.ffi) 'vlc_player_native_transport.dart'
    show nativePlayerTransport;
import 'vlc_player_native_transport_stub.dart' show VlcPlayerNativeTransport;

const _methodChannel = MethodChannel('vlc_player');

@visibleForTesting
bool debugUsePlatformChannelsForVlcPlayer = false;

Future<VlcPlayerNativeTransport>? get _nativeTransport =>
    debugUsePlatformChannelsForVlcPlayer ? null : nativePlayerTransport;

Future<T?> invokePlayer<T>(String method, Map<String, Object?> arguments) {
  final native = _nativeTransport;
  if (native == null) return _methodChannel.invokeMethod<T>(method, arguments);
  return native.then(
    (value) async => (await value.invoke(method, arguments)) as T?,
  );
}

Future<Map<String, Object?>?> invokePlayerMap(
  String method,
  Map<String, Object?> arguments,
) {
  final native = _nativeTransport;
  if (native == null) {
    return _methodChannel.invokeMapMethod<String, Object?>(method, arguments);
  }
  return native.then((value) async {
    final result = await value.invoke(method, arguments) as Map?;
    return result?.cast<String, Object?>();
  });
}

Stream<Object?> playerEvents(int viewId) {
  final native = _nativeTransport;
  if (native == null) {
    return EventChannel('vlc_player/events/$viewId').receiveBroadcastStream();
  }
  return Stream.fromFuture(native).asyncExpand((value) => value.events(viewId));
}
