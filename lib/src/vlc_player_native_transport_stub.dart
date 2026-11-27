import 'dart:async';

abstract interface class VlcPlayerNativeTransport {
  Future<Object?> invoke(String method, Map<String, Object?> arguments);
  Stream<Object?> events(int viewId);
}

const Future<VlcPlayerNativeTransport>? nativePlayerTransport = null;
