import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';

import 'vlc_player_bindings.g.dart';
import 'vlc_player_native_transport_stub.dart' show VlcPlayerNativeTransport;

const _bootstrap = MethodChannel('vlc_player/transport');
const _codec = StandardMethodCodec();
final Future<VlcPlayerNativeTransport>? nativePlayerTransport =
    Platform.isWindows || Platform.isAndroid ? _connect() : null;

Future<VlcPlayerNativeTransport> _connect() async {
  final engineId = await _bootstrap.invokeMethod<int>('engineId');
  if (engineId == null) {
    throw PlatformException(code: 'native_transport_unavailable');
  }
  final library = DynamicLibrary.open(
    Platform.isWindows ? 'vlc_player_plugin.dll' : 'libvlc_player_transport.so',
  );
  return _NativeTransport(engineId, VlcPlayerNativeBindings(library));
}

class _NativeTransport implements VlcPlayerNativeTransport {
  _NativeTransport(this._engineId, this._bindings);

  final int _engineId;
  final VlcPlayerNativeBindings _bindings;

  @override
  Future<Object?> invoke(String method, Map<String, Object?> arguments) async {
    final response = Completer<Object?>();
    final port = RawReceivePort((Object? message) {
      if (response.isCompleted) return;
      try {
        response.complete(_decode(message, method));
      } catch (error, stack) {
        response.completeError(error, stack);
      }
    });
    try {
      final encoded = _codec.encodeMethodCall(MethodCall(method, arguments));
      final bytes = encoded.buffer.asUint8List(
        encoded.offsetInBytes,
        encoded.lengthInBytes,
      );
      final request = calloc<Uint8>(bytes.length);
      try {
        request.asTypedList(bytes.length).setAll(0, bytes);
        final accepted = _bindings.vlc_player_dispatch(
          _engineId,
          port.sendPort.nativePort,
          NativeApi.postCObject.cast(),
          request,
          bytes.length,
        );
        if (accepted == 0) {
          throw PlatformException(
            code: 'native_transport_unavailable',
            message: 'The VLC player native transport is no longer attached.',
          );
        }
      } finally {
        calloc.free(request);
      }
      return await response.future;
    } finally {
      port.close();
    }
  }

  @override
  Stream<Object?> events(int viewId) {
    late final StreamController<Object?> controller;
    late final RawReceivePort port;
    late final int eventPort;
    late final Future<Object?> registration;
    controller = StreamController<Object?>(
      onListen: () {
        port = RawReceivePort((Object? message) {
          try {
            controller.add(_decode(message, 'listen'));
          } catch (error, stack) {
            controller.addError(error, stack);
          }
        })..keepIsolateAlive = false;
        eventPort = port.sendPort.nativePort;
        registration = invoke('listen', {
          'viewId': viewId,
          'eventPort': eventPort,
        });
        unawaited(
          registration.then<void>(
            (_) {},
            onError: (Object error, StackTrace stack) {
              port.close();
              controller.addError(error, stack);
            },
          ),
        );
      },
      onCancel: () async {
        port.close();
        try {
          await registration;
        } catch (_) {
          return;
        }
        await invoke('cancel', {'viewId': viewId, 'eventPort': eventPort});
      },
    );
    return controller.stream;
  }

  static Object? _decode(Object? message, String method) {
    final bytes = message as Uint8List;
    if (bytes.isEmpty) {
      throw MissingPluginException('Unknown VLC method $method');
    }
    return _codec.decodeEnvelope(ByteData.sublistView(bytes));
  }
}
