import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'vlc_player_controller.dart';

const String _viewType = 'plugins.lingjhf.com/vlc_player/view';

/// Widget that hosts the native VLC video output.
///
/// The widget creates a platform view on Android, iOS, and macOS, and a
/// texture-backed player on Windows and Linux. The owning widget should dispose
/// the [controller] when playback is no longer needed.
class VlcPlayer extends StatefulWidget {
  /// Creates a VLC player widget controlled by [controller].
  const VlcPlayer({
    super.key,
    required this.controller,
    this.backgroundColor = Colors.black,
  });

  /// Controller used to load media, control playback, and observe state.
  final VlcPlayerController controller;

  /// Background color shown behind the native video output.
  final Color backgroundColor;

  @override
  State<VlcPlayer> createState() => _VlcPlayerState();
}

class _VlcPlayerState extends State<VlcPlayer> {
  Future<int>? _textureId;
  int _textureGeneration = 0;
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    if (_usesTexturePlayer) {
      _textureId = _attachTexturePlayer(widget.controller);
    }
  }

  @override
  void didUpdateWidget(VlcPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) {
      return;
    }

    if (_usesTexturePlayer) {
      _textureId = _attachTexturePlayer(widget.controller);
      unawaited(_detachPlayer(oldWidget.controller));
    } else {
      unawaited(_detachPlayer(oldWidget.controller));
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _textureGeneration++;
    unawaited(_detachPlayer(widget.controller));
    super.dispose();
  }

  bool get _usesTexturePlayer {
    return defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux;
  }

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return ColoredBox(
        color: widget.backgroundColor,
        child: AndroidView(
          key: ValueKey<VlcPlayerController>(widget.controller),
          viewType: _viewType,
          creationParams: <String, Object?>{
            'options': widget.controller.options,
          },
          creationParamsCodec: const StandardMessageCodec(),
          onPlatformViewCreated: _handlePlatformViewCreated,
        ),
      );
    }

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return ColoredBox(
        color: widget.backgroundColor,
        child: UiKitView(
          key: ValueKey<VlcPlayerController>(widget.controller),
          viewType: _viewType,
          creationParams: <String, Object?>{
            'options': widget.controller.options,
          },
          creationParamsCodec: const StandardMessageCodec(),
          onPlatformViewCreated: _handlePlatformViewCreated,
        ),
      );
    }

    if (_usesTexturePlayer) {
      return ColoredBox(
        color: widget.backgroundColor,
        child: FutureBuilder<int>(
          future: _textureId,
          builder: (context, snapshot) {
            final textureId = snapshot.data;
            if (textureId != null) {
              return Texture(textureId: textureId);
            }
            if (snapshot.hasError) {
              return Center(
                child: Text(
                  snapshot.error.toString(),
                  textAlign: TextAlign.center,
                ),
              );
            }
            return const Center(child: CircularProgressIndicator());
          },
        ),
      );
    }

    if (defaultTargetPlatform != TargetPlatform.macOS) {
      return ColoredBox(
        color: widget.backgroundColor,
        child: const Center(
          child: Text(
            'vlc_player currently supports Android, iOS, macOS, Windows and Linux only.',
          ),
        ),
      );
    }

    return ColoredBox(
      color: widget.backgroundColor,
      child: AppKitView(
        key: ValueKey<VlcPlayerController>(widget.controller),
        viewType: _viewType,
        creationParams: <String, Object?>{'options': widget.controller.options},
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: _handlePlatformViewCreated,
      ),
    );
  }

  void _handlePlatformViewCreated(int viewId) {
    unawaited(_attachPlatformView(widget.controller, viewId));
  }

  Future<int> _attachTexturePlayer(VlcPlayerController controller) async {
    final generation = ++_textureGeneration;
    final textureId = await _attachTextureBackedPlayer(controller);
    if (_isDisposed ||
        generation != _textureGeneration ||
        widget.controller != controller) {
      await _detachPlayer(controller);
    }
    return textureId;
  }

  Future<void> _attachPlatformView(VlcPlayerController controller, int viewId) {
    return (controller as dynamic).attach(viewId) as Future<void>;
  }

  Future<int> _attachTextureBackedPlayer(VlcPlayerController controller) {
    return (controller as dynamic).attachTexturePlayer() as Future<int>;
  }

  Future<void> _detachPlayer(VlcPlayerController controller) {
    return (controller as dynamic).detach() as Future<void>;
  }
}
