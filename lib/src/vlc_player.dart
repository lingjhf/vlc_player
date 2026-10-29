import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'vlc_player_controller.dart';
import 'vlc_player_controller_internals.dart';
import 'vlc_player_value.dart';

const String _viewType = 'plugins.lingjhf.com/vlc_player/view';

/// How video should be fitted inside the `VlcPlayer` widget bounds.
enum VlcVideoFit {
  /// Preserve the video aspect ratio and show the full frame.
  contain,

  /// Preserve the video aspect ratio and cover the full widget bounds.
  cover,

  /// Stretch the video to fill the widget bounds.
  fill,

  /// Render the video at its natural decoded size when available.
  none,
}

/// Widget that hosts the native VLC video output.
///
/// The widget creates a platform view on Android, iOS, and macOS, and a
/// texture-backed player on Windows and Linux. The owning widget should dispose
/// the [controller] when playback is no longer needed.
/// A controller can belong to only one mounted player widget at a time.
class VlcPlayer extends StatefulWidget {
  /// Creates a VLC player widget controlled by [controller].
  const VlcPlayer({
    super.key,
    required this.controller,
    this.backgroundColor = Colors.black,
    this.fit = VlcVideoFit.contain,
  });

  /// Controller used to load media, control playback, and observe state.
  final VlcPlayerController controller;

  /// Background color shown behind the native video output.
  final Color backgroundColor;

  /// How video should be fitted inside this widget.
  final VlcVideoFit fit;

  @override
  State<VlcPlayer> createState() => _VlcPlayerState();
}

class _VlcPlayerState extends State<VlcPlayer> {
  Future<int>? _textureId;
  VlcPlayerBinding? _binding;
  StateError? _bindingError;

  @override
  void initState() {
    super.initState();
    _bindController();
  }

  @override
  void didUpdateWidget(VlcPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller &&
        (_usesTexturePlayer || oldWidget.fit == widget.fit)) {
      return;
    }
    unawaited(_binding?.dispose());
    _bindController();
  }

  @override
  void dispose() {
    unawaited(_binding?.dispose());
    super.dispose();
  }

  bool get _usesTexturePlayer {
    return defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux;
  }

  @override
  Widget build(BuildContext context) {
    final binding = _binding;
    if (binding == null) {
      return ColoredBox(
        color: widget.backgroundColor,
        child: Center(
          child: Text(_bindingError.toString(), textAlign: TextAlign.center),
        ),
      );
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      return ColoredBox(
        color: widget.backgroundColor,
        child: AndroidView(
          key: ValueKey<String>(_platformViewKey),
          viewType: _viewType,
          creationParams: <String, Object?>{
            'options': widget.controller.options,
            'fit': widget.fit.name,
          },
          creationParamsCodec: const StandardMessageCodec(),
          onPlatformViewCreated: (id) => _attachPlatformView(binding, id),
        ),
      );
    }

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return ColoredBox(
        color: widget.backgroundColor,
        child: UiKitView(
          key: ValueKey<String>(_platformViewKey),
          viewType: _viewType,
          creationParams: <String, Object?>{
            'options': widget.controller.options,
            'fit': widget.fit.name,
          },
          creationParamsCodec: const StandardMessageCodec(),
          onPlatformViewCreated: (id) => _attachPlatformView(binding, id),
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
              return ValueListenableBuilder<VlcPlayerValue>(
                valueListenable: widget.controller,
                builder: (context, value, child) {
                  return _fitTexture(textureId, value.videoSize);
                },
              );
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
        key: ValueKey<String>(_platformViewKey),
        viewType: _viewType,
        creationParams: <String, Object?>{
          'options': widget.controller.options,
          'fit': widget.fit.name,
        },
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: (id) => _attachPlatformView(binding, id),
      ),
    );
  }

  void _attachPlatformView(VlcPlayerBinding binding, int viewId) {
    unawaited(() async {
      try {
        await binding.attach(viewId);
      } catch (_) {
        if (!binding.isDisposed) rethrow;
      }
    }());
  }

  String get _platformViewKey {
    return '${identityHashCode(widget.controller)}-${widget.fit.name}';
  }

  VlcPlayerBinding _claimController() {
    return (widget.controller as VlcPlayerControllerInternals).createBinding();
  }

  void _bindController() {
    try {
      _binding = _claimController();
      _bindingError = null;
      if (_usesTexturePlayer) _textureId = _binding!.attachTexturePlayer();
    } on StateError catch (error) {
      _binding = null;
      _bindingError = error;
      _textureId = null;
    }
  }

  Widget _fitTexture(int textureId, Size? videoSize) {
    final texture = Texture(textureId: textureId);
    final size = videoSize;
    if (widget.fit == VlcVideoFit.fill || size == null) {
      return SizedBox.expand(child: texture);
    }

    final sizedTexture = SizedBox(
      width: size.width,
      height: size.height,
      child: texture,
    );
    return Center(
      child: FittedBox(
        fit: switch (widget.fit) {
          VlcVideoFit.contain => BoxFit.contain,
          VlcVideoFit.cover => BoxFit.cover,
          VlcVideoFit.none => BoxFit.none,
          VlcVideoFit.fill => BoxFit.fill,
        },
        child: sizedTexture,
      ),
    );
  }
}
