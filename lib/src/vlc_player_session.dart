import 'dart:async';

import 'package:flutter/services.dart';

import 'vlc_player_controller_internals.dart';

/// Owns native resources for one widget, including unfinished attachments.
class VlcPlayerSession implements VlcPlayerBinding {
  VlcPlayerSession({
    required this.createPlayer,
    required this.disposePlayer,
    required this.onAttached,
    required this.onDetached,
    required this.onEvent,
    required this.onError,
  });

  final Future<Map<String, Object?>?> Function() createPlayer;
  final Future<void> Function(int viewId) disposePlayer;
  final Future<void> Function(int viewId) onAttached;
  final void Function() onDetached;
  final void Function(Object? event) onEvent;
  final void Function(Object error) onError;

  _PlayerAttachment? _attachment;
  bool _isDisposed = false;
  Future<void>? _release;

  @override
  bool get isDisposed => _isDisposed;

  int? get viewId {
    final attachment = _attachment;
    return attachment != null && attachment.attached && !attachment.closed
        ? attachment.viewId
        : null;
  }

  @override
  Future<void> attach(int viewId) async {
    if (_isDisposed) {
      // PlatformView creation can finish after its widget has gone away.
      await disposePlayer(viewId);
      throw StateError('The player binding has been disposed.');
    }
    final current = _attachment;
    if (current != null && !current.texture && current.viewId == viewId) {
      await current.ready;
      return;
    }
    await _start(_PlayerAttachment(disposePlayer, viewId: viewId));
  }

  @override
  Future<int> attachTexturePlayer() async {
    if (_isDisposed) {
      throw StateError('The player binding has been disposed.');
    }
    final current = _attachment;
    final attachment = current != null && current.texture
        ? current
        : _PlayerAttachment(disposePlayer, texture: true);
    if (!identical(current, attachment)) {
      unawaited(_start(attachment));
    }
    await attachment.ready;
    return attachment.textureId!;
  }

  Future<void> _start(_PlayerAttachment attachment) {
    final previous = _attachment;
    _attachment = attachment;
    onDetached();
    attachment.ready = _initialize(attachment, previous);
    return attachment.ready;
  }

  Future<void> _initialize(
    _PlayerAttachment attachment,
    _PlayerAttachment? previous,
  ) async {
    try {
      await previous?.release();
      _ensureCurrent(attachment);
      if (attachment.texture) {
        final response = await createPlayer();
        attachment.viewId = (response?['viewId'] as num?)?.toInt();
        attachment.textureId = (response?['textureId'] as num?)?.toInt();
        if (attachment.viewId == null || attachment.textureId == null) {
          throw StateError(
            'vlc_player texture creation returned invalid data.',
          );
        }
      }
      _ensureCurrent(attachment);
      attachment.attached = true;
      attachment.subscription =
          EventChannel(
            'vlc_player/events/${attachment.viewId}',
          ).receiveBroadcastStream().listen(
            (event) {
              if (_isCurrent(attachment)) onEvent(event);
            },
            onError: (Object error) {
              if (_isCurrent(attachment)) onError(error);
            },
          );
      await onAttached(attachment.viewId!);
      _ensureCurrent(attachment);
    } catch (_) {
      if (identical(_attachment, attachment)) {
        _attachment = null;
        onDetached();
      }
      await attachment.release();
      rethrow;
    }
  }

  bool _isCurrent(_PlayerAttachment attachment) =>
      !_isDisposed && !attachment.closed && identical(_attachment, attachment);

  void _ensureCurrent(_PlayerAttachment attachment) {
    if (!_isCurrent(attachment)) {
      throw StateError('The player attachment is no longer active.');
    }
  }

  @override
  Future<void> dispose() {
    if (_isDisposed) return _release!;
    _isDisposed = true;
    final attachment = _attachment;
    _attachment = null;
    onDetached();
    // A late create response is released by _initialize, without blocking a
    // replacement widget on an unfinished native create request.
    return _release = attachment?.release() ?? Future<void>.value();
  }
}

class _PlayerAttachment {
  _PlayerAttachment(this.disposePlayer, {this.viewId, this.texture = false});

  final Future<void> Function(int viewId) disposePlayer;
  final bool texture;
  int? viewId;
  int? textureId;
  bool attached = false;
  bool closed = false;
  late Future<void> ready;
  StreamSubscription<Object?>? subscription;
  Future<void>? _cancelSubscription;
  Future<void>? _disposeNative;

  Future<void> release() async {
    closed = true;
    _cancelSubscription ??= subscription?.cancel() ?? Future<void>.value();
    subscription = null;
    try {
      await _cancelSubscription;
    } finally {
      // viewId may arrive after an earlier release during native creation.
      final id = viewId;
      if (id != null) {
        await (_disposeNative ??= disposePlayer(id));
      }
    }
  }
}
