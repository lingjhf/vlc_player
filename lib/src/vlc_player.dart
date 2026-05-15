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
  Future<int>? _windowsTextureId;

  @override
  void initState() {
    super.initState();
    if (defaultTargetPlatform == TargetPlatform.windows) {
      _windowsTextureId = widget.controller.attachTextureForWindows();
    }
  }

  @override
  void didUpdateWidget(VlcPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (defaultTargetPlatform != TargetPlatform.windows ||
        oldWidget.controller == widget.controller) {
      return;
    }
    unawaited(oldWidget.controller.detach());
    _windowsTextureId = widget.controller.attachTextureForWindows();
  }

  @override
  void dispose() {
    if (defaultTargetPlatform == TargetPlatform.windows) {
      unawaited(widget.controller.detach());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return ColoredBox(
        color: widget.backgroundColor,
        child: AndroidView(
          viewType: VlcPlayerController.viewType,
          creationParams: <String, Object?>{
            'options': widget.controller.options,
          },
          creationParamsCodec: const StandardMessageCodec(),
          onPlatformViewCreated: widget.controller.attach,
        ),
      );
    }

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return ColoredBox(
        color: widget.backgroundColor,
        child: UiKitView(
          viewType: VlcPlayerController.viewType,
          creationParams: <String, Object?>{
            'options': widget.controller.options,
          },
          creationParamsCodec: const StandardMessageCodec(),
          onPlatformViewCreated: widget.controller.attach,
        ),
      );
    }

    if (defaultTargetPlatform == TargetPlatform.windows) {
      return ColoredBox(
        color: widget.backgroundColor,
        child: FutureBuilder<int>(
          future: _windowsTextureId,
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
            'vlc_player currently supports Android, iOS, macOS and Windows only.',
          ),
        ),
      );
    }

    return ColoredBox(
      color: widget.backgroundColor,
      child: AppKitView(
        viewType: VlcPlayerController.viewType,
        creationParams: <String, Object?>{'options': widget.controller.options},
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: widget.controller.attach,
      ),
    );
  }
}
