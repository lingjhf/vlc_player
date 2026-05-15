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

    if (defaultTargetPlatform != TargetPlatform.macOS) {
      return ColoredBox(
        color: widget.backgroundColor,
        child: const Center(
          child: Text(
            'vlc_player currently supports Android, iOS and macOS only.',
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
