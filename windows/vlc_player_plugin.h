#ifndef FLUTTER_PLUGIN_VLC_PLAYER_PLUGIN_H_
#define FLUTTER_PLUGIN_VLC_PLAYER_PLUGIN_H_

#include <flutter/binary_messenger.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/texture_registrar.h>

#include <memory>
#include <unordered_map>

namespace vlc_player {

class WindowsVlcPlayer;

class VlcPlayerPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  VlcPlayerPlugin(flutter::BinaryMessenger *messenger,
                  flutter::TextureRegistrar *texture_registrar);

  virtual ~VlcPlayerPlugin();

  VlcPlayerPlugin(const VlcPlayerPlugin &) = delete;
  VlcPlayerPlugin &operator=(const VlcPlayerPlugin &) = delete;

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

 private:
  WindowsVlcPlayer *FindPlayer(
      const flutter::EncodableMap &arguments,
      flutter::MethodResult<flutter::EncodableValue> *result);

  void DisposePlayer(int64_t view_id);

  flutter::BinaryMessenger *messenger_;
  flutter::TextureRegistrar *texture_registrar_;
  int64_t next_view_id_ = 1;
  std::unordered_map<int64_t, std::unique_ptr<WindowsVlcPlayer>> players_;
};

}  // namespace vlc_player

#endif  // FLUTTER_PLUGIN_VLC_PLAYER_PLUGIN_H_
