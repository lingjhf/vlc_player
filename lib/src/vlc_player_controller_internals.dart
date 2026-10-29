/// Internal controller hooks used by `VlcPlayer`.
///
/// This file is intentionally not exported from `package:vlc_player/vlc_player.dart`.
abstract interface class VlcPlayerControllerInternals {
  /// Claims this controller for one widget until the binding is disposed.
  VlcPlayerBinding createBinding();
}

/// A widget's exclusive, independently disposable claim on a controller.
abstract interface class VlcPlayerBinding {
  bool get isDisposed;

  /// Attaches a platform view owned by this binding.
  Future<void> attach(int viewId);

  /// Attaches the controller to a texture-backed native player.
  Future<int> attachTexturePlayer();

  /// Invalidates this binding immediately and releases its native player.
  Future<void> dispose();
}
