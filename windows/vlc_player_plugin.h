#ifndef FLUTTER_PLUGIN_VLC_PLAYER_PLUGIN_H_
#define FLUTTER_PLUGIN_VLC_PLAYER_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace vlc_player {

class VlcPlayerPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  VlcPlayerPlugin();

  virtual ~VlcPlayerPlugin();

  // Disallow copy and assign.
  VlcPlayerPlugin(const VlcPlayerPlugin&) = delete;
  VlcPlayerPlugin& operator=(const VlcPlayerPlugin&) = delete;

  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

}  // namespace vlc_player

#endif  // FLUTTER_PLUGIN_VLC_PLAYER_PLUGIN_H_
