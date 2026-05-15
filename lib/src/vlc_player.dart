import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'vlc_player_controller.dart';

class VlcPlayer extends StatefulWidget {
  const VlcPlayer({
    super.key,
    required this.controller,
    this.backgroundColor = Colors.black,
  });

  final VlcPlayerController controller;
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
      unawaited(oldWidget.controller.detach());
    } else {
      unawaited(oldWidget.controller.detach());
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _textureGeneration++;
    unawaited(widget.controller.detach());
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
          viewType: VlcPlayerController.viewType,
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
          viewType: VlcPlayerController.viewType,
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
        viewType: VlcPlayerController.viewType,
        creationParams: <String, Object?>{'options': widget.controller.options},
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: _handlePlatformViewCreated,
      ),
    );
  }

  void _handlePlatformViewCreated(int viewId) {
    unawaited(widget.controller.attach(viewId));
  }

  Future<int> _attachTexturePlayer(VlcPlayerController controller) async {
    final generation = ++_textureGeneration;
    final textureId = await controller.attachTexturePlayer();
    if (_isDisposed ||
        generation != _textureGeneration ||
        widget.controller != controller) {
      await controller.detach();
    }
    return textureId;
  }
}
