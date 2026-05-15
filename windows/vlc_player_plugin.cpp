#include "vlc_player_plugin.h"

#include <windows.h>

#include <flutter/event_channel.h>
#include <flutter/event_sink.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <flutter/texture_registrar.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstring>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <utility>
#include <vector>

namespace vlc_player {
namespace {

using EncodableList = flutter::EncodableList;
using EncodableMap = flutter::EncodableMap;
using EncodableValue = flutter::EncodableValue;

struct libvlc_instance_t;
struct libvlc_media_t;
struct libvlc_media_player_t;

using libvlc_video_lock_cb = void *(*)(void *opaque, void **planes);
using libvlc_video_unlock_cb = void (*)(void *opaque, void *picture,
                                        void *const *planes);
using libvlc_video_display_cb = void (*)(void *opaque, void *picture);
using libvlc_video_format_cb = unsigned (*)(void **opaque, char *chroma,
                                            unsigned *width, unsigned *height,
                                            unsigned *pitches,
                                            unsigned *lines);
using libvlc_video_cleanup_cb = void (*)(void *opaque);

class LibVlcApi {
 public:
  static LibVlcApi &Instance() {
    static LibVlcApi api;
    return api;
  }

  bool available() const { return available_; }
  const std::string &error() const { return error_; }

  libvlc_instance_t *(*new_instance)(int argc, const char *const *argv) =
      nullptr;
  void (*release_instance)(libvlc_instance_t *instance) = nullptr;
  libvlc_media_player_t *(*media_player_new)(libvlc_instance_t *instance) =
      nullptr;
  void (*media_player_release)(libvlc_media_player_t *player) = nullptr;
  libvlc_media_t *(*media_new_location)(libvlc_instance_t *instance,
                                        const char *uri) = nullptr;
  void (*media_release)(libvlc_media_t *media) = nullptr;
  void (*media_add_option)(libvlc_media_t *media, const char *option) =
      nullptr;
  void (*media_player_set_media)(libvlc_media_player_t *player,
                                 libvlc_media_t *media) = nullptr;
  int (*media_player_play)(libvlc_media_player_t *player) = nullptr;
  void (*media_player_pause)(libvlc_media_player_t *player) = nullptr;
  void (*media_player_stop)(libvlc_media_player_t *player) = nullptr;
  void (*media_player_set_time)(libvlc_media_player_t *player,
                                int64_t time) = nullptr;
  int64_t (*media_player_get_time)(libvlc_media_player_t *player) = nullptr;
  int64_t (*media_player_get_length)(libvlc_media_player_t *player) = nullptr;
  int (*audio_set_volume)(libvlc_media_player_t *player, int volume) = nullptr;
  int (*media_player_set_rate)(libvlc_media_player_t *player,
                               float rate) = nullptr;
  float (*media_player_get_rate)(libvlc_media_player_t *player) = nullptr;
  int (*media_player_get_state)(libvlc_media_player_t *player) = nullptr;
  void (*video_set_callbacks)(libvlc_media_player_t *player,
                              libvlc_video_lock_cb lock,
                              libvlc_video_unlock_cb unlock,
                              libvlc_video_display_cb display,
                              void *opaque) = nullptr;
  void (*video_set_format_callbacks)(libvlc_media_player_t *player,
                                     libvlc_video_format_cb setup,
                                     libvlc_video_cleanup_cb cleanup) =
      nullptr;

 private:
  LibVlcApi() {
    module_ = LoadLibraryW(L"libvlc.dll");
    if (module_ == nullptr) {
      error_ =
          "Unable to load libvlc.dll. Install VLC or bundle the VLC runtime "
          "with the Windows app.";
      return;
    }

    available_ =
        Load("libvlc_new", new_instance) &&
        Load("libvlc_release", release_instance) &&
        Load("libvlc_media_player_new", media_player_new) &&
        Load("libvlc_media_player_release", media_player_release) &&
        Load("libvlc_media_new_location", media_new_location) &&
        Load("libvlc_media_release", media_release) &&
        Load("libvlc_media_add_option", media_add_option) &&
        Load("libvlc_media_player_set_media", media_player_set_media) &&
        Load("libvlc_media_player_play", media_player_play) &&
        Load("libvlc_media_player_pause", media_player_pause) &&
        Load("libvlc_media_player_stop", media_player_stop) &&
        Load("libvlc_media_player_set_time", media_player_set_time) &&
        Load("libvlc_media_player_get_time", media_player_get_time) &&
        Load("libvlc_media_player_get_length", media_player_get_length) &&
        Load("libvlc_audio_set_volume", audio_set_volume) &&
        Load("libvlc_media_player_set_rate", media_player_set_rate) &&
        Load("libvlc_media_player_get_rate", media_player_get_rate) &&
        Load("libvlc_media_player_get_state", media_player_get_state) &&
        Load("libvlc_video_set_callbacks", video_set_callbacks) &&
        Load("libvlc_video_set_format_callbacks", video_set_format_callbacks);
  }

  template <typename T>
  bool Load(const char *name, T &target) {
    target = reinterpret_cast<T>(GetProcAddress(module_, name));
    if (target == nullptr && error_.empty()) {
      error_ = std::string("Missing VLC runtime symbol: ") + name;
    }
    return target != nullptr;
  }

  HMODULE module_ = nullptr;
  bool available_ = false;
  std::string error_;
};

const EncodableValue *FindValue(const EncodableMap &map, const char *key) {
  auto it = map.find(EncodableValue(key));
  return it == map.end() ? nullptr : &it->second;
}

bool ReadInt64(const EncodableMap &map, const char *key, int64_t *value) {
  const EncodableValue *raw = FindValue(map, key);
  if (raw == nullptr) {
    return false;
  }
  if (const auto int_value = std::get_if<int32_t>(raw)) {
    *value = *int_value;
    return true;
  }
  if (const auto long_value = std::get_if<int64_t>(raw)) {
    *value = *long_value;
    return true;
  }
  return false;
}

bool ReadDouble(const EncodableMap &map, const char *key, double *value) {
  const EncodableValue *raw = FindValue(map, key);
  if (raw == nullptr) {
    return false;
  }
  if (const auto double_value = std::get_if<double>(raw)) {
    *value = *double_value;
    return true;
  }
  if (const auto int_value = std::get_if<int32_t>(raw)) {
    *value = *int_value;
    return true;
  }
  if (const auto long_value = std::get_if<int64_t>(raw)) {
    *value = static_cast<double>(*long_value);
    return true;
  }
  return false;
}

std::string ReadString(const EncodableMap &map, const char *key) {
  const EncodableValue *raw = FindValue(map, key);
  if (raw == nullptr) {
    return "";
  }
  if (const auto string_value = std::get_if<std::string>(raw)) {
    return *string_value;
  }
  return "";
}

bool ReadBool(const EncodableMap &map, const char *key) {
  const EncodableValue *raw = FindValue(map, key);
  if (raw == nullptr) {
    return false;
  }
  if (const auto bool_value = std::get_if<bool>(raw)) {
    return *bool_value;
  }
  return false;
}

std::vector<std::string> ReadStringList(const EncodableMap &map,
                                        const char *key) {
  std::vector<std::string> values;
  const EncodableValue *raw = FindValue(map, key);
  const auto list = raw == nullptr ? nullptr : std::get_if<EncodableList>(raw);
  if (list == nullptr) {
    return values;
  }
  for (const auto &item : *list) {
    if (const auto string_value = std::get_if<std::string>(&item)) {
      values.push_back(*string_value);
    }
  }
  return values;
}

std::vector<std::string> ReadHeaders(const EncodableMap &map) {
  std::vector<std::string> headers;
  const EncodableValue *raw = FindValue(map, "httpHeaders");
  const auto header_map =
      raw == nullptr ? nullptr : std::get_if<EncodableMap>(raw);
  if (header_map == nullptr) {
    return headers;
  }

  for (const auto &entry : *header_map) {
    const auto name = std::get_if<std::string>(&entry.first);
    const auto value = std::get_if<std::string>(&entry.second);
    if (name == nullptr || value == nullptr || name->empty() ||
        name->find('\r') != std::string::npos ||
        name->find('\n') != std::string::npos ||
        value->find('\r') != std::string::npos ||
        value->find('\n') != std::string::npos) {
      continue;
    }
    headers.push_back(":http-header=" + *name + ": " + *value);
  }
  return headers;
}

std::string StateName(int state) {
  switch (state) {
    case 1:
      return "opening";
    case 2:
      return "buffering";
    case 3:
      return "playing";
    case 4:
      return "paused";
    case 5:
      return "stopped";
    case 6:
      return "ended";
    case 7:
      return "error";
    default:
      return "idle";
  }
}

}  // namespace

class WindowsVlcPlayer {
 public:
  WindowsVlcPlayer(int64_t view_id, flutter::BinaryMessenger *messenger,
                   flutter::TextureRegistrar *texture_registrar,
                   const std::vector<std::string> &options)
      : texture_registrar_(texture_registrar),
        event_channel_(messenger, "vlc_player/events/" + std::to_string(view_id),
                       &flutter::StandardMethodCodec::GetInstance()) {
    auto stream_handler =
        std::make_unique<flutter::StreamHandlerFunctions<EncodableValue>>(
            [this](const EncodableValue *arguments,
                   std::unique_ptr<flutter::EventSink<EncodableValue>> &&events)
                -> std::unique_ptr<
                    flutter::StreamHandlerError<EncodableValue>> {
              {
                std::lock_guard<std::mutex> lock(event_mutex_);
                event_sink_ = std::move(events);
              }
              SendSnapshot();
              return nullptr;
            },
            [this](const EncodableValue *arguments)
                -> std::unique_ptr<
                    flutter::StreamHandlerError<EncodableValue>> {
              std::lock_guard<std::mutex> lock(event_mutex_);
              event_sink_.reset();
              return nullptr;
            });
    event_channel_.SetStreamHandler(std::move(stream_handler));

    auto &api = LibVlcApi::Instance();
    std::vector<const char *> argv;
    argv.reserve(options.size());
    for (const auto &option : options) {
      argv.push_back(option.c_str());
    }

    instance_ = api.new_instance(static_cast<int>(argv.size()), argv.data());
    if (instance_ == nullptr) {
      init_error_ = "Unable to create VLC instance.";
      return;
    }

    player_ = api.media_player_new(instance_);
    if (player_ == nullptr) {
      init_error_ = "Unable to create VLC media player.";
      return;
    }

    api.video_set_callbacks(player_, &WindowsVlcPlayer::Lock,
                            &WindowsVlcPlayer::Unlock,
                            &WindowsVlcPlayer::Display, this);
    api.video_set_format_callbacks(player_, &WindowsVlcPlayer::SetupFormat,
                                   &WindowsVlcPlayer::CleanupFormat);

    texture_ = std::make_unique<flutter::TextureVariant>(
        flutter::PixelBufferTexture([this](size_t width, size_t height) {
          return CopyPixelBuffer(width, height);
        }));
    texture_id_ = texture_registrar_->RegisterTexture(texture_.get());
    polling_ = true;
    polling_thread_ = std::thread([this] {
      while (polling_.load()) {
        std::this_thread::sleep_for(std::chrono::milliseconds(500));
        SendSnapshot();
      }
    });
  }

  ~WindowsVlcPlayer() { Dispose(); }

  bool is_valid() const { return init_error_.empty() && texture_id_ != -1; }
  const std::string &error() const { return init_error_; }
  int64_t texture_id() const { return texture_id_; }

  std::string SetSource(const std::string &uri,
                        const std::vector<std::string> &headers,
                        bool auto_play) {
    if (const auto error = ActiveError(); !error.empty()) {
      return error;
    }
    if (uri.empty()) {
      return "A non-empty uri is required.";
    }

    auto &api = LibVlcApi::Instance();
    libvlc_media_t *media = api.media_new_location(instance_, uri.c_str());
    if (media == nullptr) {
      return "Unable to create VLC media.";
    }

    for (const auto &header : headers) {
      api.media_add_option(media, header.c_str());
    }

    api.media_player_set_media(player_, media);
    api.media_release(media);
    state_override_ = "opening";
    error_description_.clear();
    SendSnapshot();

    if (auto_play) {
      return Play();
    }
    return "";
  }

  std::string Play() {
    if (const auto error = ActiveError(); !error.empty()) {
      return error;
    }
    if (LibVlcApi::Instance().media_player_play(player_) != 0) {
      return "VLC failed to start playback.";
    }
    state_override_.clear();
    SendSnapshot();
    return "";
  }

  std::string Pause() {
    if (const auto error = ActiveError(); !error.empty()) {
      return error;
    }
    LibVlcApi::Instance().media_player_pause(player_);
    state_override_.clear();
    SendSnapshot();
    return "";
  }

  std::string Stop() {
    if (const auto error = ActiveError(); !error.empty()) {
      return error;
    }
    LibVlcApi::Instance().media_player_stop(player_);
    state_override_ = "stopped";
    SendSnapshot();
    return "";
  }

  std::string SeekTo(int64_t milliseconds) {
    if (const auto error = ActiveError(); !error.empty()) {
      return error;
    }
    LibVlcApi::Instance().media_player_set_time(
        player_, std::max<int64_t>(0, milliseconds));
    SendSnapshot();
    return "";
  }

  std::string SetVolume(int volume) {
    if (const auto error = ActiveError(); !error.empty()) {
      return error;
    }
    volume_ = std::clamp(volume, 0, 200);
    LibVlcApi::Instance().audio_set_volume(player_, volume_);
    SendSnapshot();
    return "";
  }

  std::string SetPlaybackSpeed(double speed) {
    if (const auto error = ActiveError(); !error.empty()) {
      return error;
    }
    playback_speed_ = std::max(0.01, speed);
    LibVlcApi::Instance().media_player_set_rate(
        player_, static_cast<float>(playback_speed_));
    SendSnapshot();
    return "";
  }

  void Dispose() {
    if (disposed_.exchange(true)) {
      return;
    }
    polling_ = false;
    if (polling_thread_.joinable()) {
      polling_thread_.join();
    }

    {
      std::lock_guard<std::mutex> lock(event_mutex_);
      event_sink_.reset();
    }
    event_channel_.SetStreamHandler(nullptr);

    auto &api = LibVlcApi::Instance();
    if (player_ != nullptr) {
      api.media_player_stop(player_);
      api.media_player_release(player_);
      player_ = nullptr;
    }
    if (instance_ != nullptr) {
      api.release_instance(instance_);
      instance_ = nullptr;
    }
    if (texture_id_ != -1) {
      texture_registrar_->UnregisterTexture(texture_id_);
      texture_id_ = -1;
    }
    texture_.reset();
  }

 private:
  static unsigned SetupFormat(void **opaque, char *chroma, unsigned *width,
                              unsigned *height, unsigned *pitches,
                              unsigned *lines) {
    auto *player = static_cast<WindowsVlcPlayer *>(*opaque);
    std::memcpy(chroma, "RGBA", 4);
    pitches[0] = *width * 4;
    lines[0] = *height;
    player->ResizeVideoBuffer(*width, *height, pitches[0]);
    return 1;
  }

  static void CleanupFormat(void *opaque) {}

  static void *Lock(void *opaque, void **planes) {
    auto *player = static_cast<WindowsVlcPlayer *>(opaque);
    player->video_mutex_.lock();
    if (player->frame_buffer_.empty()) {
      player->video_mutex_.unlock();
      planes[0] = nullptr;
      return nullptr;
    }
    planes[0] = player->frame_buffer_.data();
    return nullptr;
  }

  static void Unlock(void *opaque, void *picture, void *const *planes) {
    auto *player = static_cast<WindowsVlcPlayer *>(opaque);
    player->render_buffer_ = player->frame_buffer_;
    player->pixel_buffer_.buffer = player->render_buffer_.data();
    player->video_mutex_.unlock();
  }

  static void Display(void *opaque, void *picture) {
    auto *player = static_cast<WindowsVlcPlayer *>(opaque);
    if (!player->disposed_.load() && player->texture_id_ != -1) {
      player->texture_registrar_->MarkTextureFrameAvailable(player->texture_id_);
    }
  }

  const FlutterDesktopPixelBuffer *CopyPixelBuffer(size_t width,
                                                   size_t height) {
    std::lock_guard<std::mutex> lock(video_mutex_);
    if (render_buffer_.empty()) {
      return nullptr;
    }
    return &pixel_buffer_;
  }

  void ResizeVideoBuffer(unsigned width, unsigned height, unsigned pitch) {
    std::lock_guard<std::mutex> lock(video_mutex_);
    frame_buffer_.assign(static_cast<size_t>(pitch) * height, 0);
    render_buffer_ = frame_buffer_;
    pixel_buffer_.buffer = render_buffer_.data();
    pixel_buffer_.width = width;
    pixel_buffer_.height = height;
    pixel_buffer_.release_callback = nullptr;
    pixel_buffer_.release_context = nullptr;
  }

  std::string ActiveError() const {
    if (disposed_.load()) {
      return "The vlc_player has been disposed.";
    }
    if (!init_error_.empty()) {
      return init_error_;
    }
    if (player_ == nullptr) {
      return "The VLC media player is not available.";
    }
    return "";
  }

  void SendSnapshot() {
    if (disposed_.load() || player_ == nullptr) {
      return;
    }

    auto &api = LibVlcApi::Instance();
    const int state = api.media_player_get_state(player_);
    if (state == 7) {
      error_description_ = "VLC encountered an error while playing the media.";
    }

    EncodableMap event;
    event[EncodableValue("state")] =
        EncodableValue(state_override_.empty() ? StateName(state)
                                               : state_override_);
    event[EncodableValue("position")] = EncodableValue(
        std::max<int64_t>(0, api.media_player_get_time(player_)));
    event[EncodableValue("duration")] = EncodableValue(
        std::max<int64_t>(0, api.media_player_get_length(player_)));
    event[EncodableValue("volume")] = EncodableValue(volume_);
    event[EncodableValue("playbackSpeed")] =
        EncodableValue(static_cast<double>(api.media_player_get_rate(player_)));
    if (!error_description_.empty()) {
      event[EncodableValue("errorDescription")] =
          EncodableValue(error_description_);
    }

    std::lock_guard<std::mutex> lock(event_mutex_);
    if (event_sink_) {
      event_sink_->Success(EncodableValue(event));
    }
  }

  flutter::TextureRegistrar *texture_registrar_;
  flutter::EventChannel<EncodableValue> event_channel_;
  std::unique_ptr<flutter::EventSink<EncodableValue>> event_sink_;
  std::mutex event_mutex_;

  libvlc_instance_t *instance_ = nullptr;
  libvlc_media_player_t *player_ = nullptr;
  std::string init_error_;
  std::atomic<bool> disposed_ = false;
  std::atomic<bool> polling_ = false;
  std::thread polling_thread_;

  std::unique_ptr<flutter::TextureVariant> texture_;
  int64_t texture_id_ = -1;
  FlutterDesktopPixelBuffer pixel_buffer_ = {};
  std::mutex video_mutex_;
  std::vector<uint8_t> frame_buffer_;
  std::vector<uint8_t> render_buffer_;

  int volume_ = 100;
  double playback_speed_ = 1.0;
  std::string state_override_;
  std::string error_description_;
};

// static
void VlcPlayerPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<EncodableValue>>(
          registrar->messenger(), "vlc_player",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<VlcPlayerPlugin>(
      registrar->messenger(), registrar->texture_registrar());

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto &call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

VlcPlayerPlugin::VlcPlayerPlugin(flutter::BinaryMessenger *messenger,
                                 flutter::TextureRegistrar *texture_registrar)
    : messenger_(messenger), texture_registrar_(texture_registrar) {}

VlcPlayerPlugin::~VlcPlayerPlugin() {
  players_.clear();
}

void VlcPlayerPlugin::HandleMethodCall(
    const flutter::MethodCall<EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  const auto *arguments = std::get_if<EncodableMap>(method_call.arguments());

  if (method_call.method_name() == "create") {
    auto &api = LibVlcApi::Instance();
    if (!api.available()) {
      result->Error("vlc_not_found", api.error());
      return;
    }

    const auto options = arguments == nullptr
                             ? std::vector<std::string>()
                             : ReadStringList(*arguments, "options");
    const int64_t view_id = next_view_id_++;
    auto player = std::make_unique<WindowsVlcPlayer>(
        view_id, messenger_, texture_registrar_, options);
    if (!player->is_valid()) {
      result->Error("create_failed", player->error());
      return;
    }

    const int64_t texture_id = player->texture_id();
    players_[view_id] = std::move(player);

    EncodableMap response;
    response[EncodableValue("viewId")] = EncodableValue(view_id);
    response[EncodableValue("textureId")] = EncodableValue(texture_id);
    result->Success(EncodableValue(response));
    return;
  }

  if (arguments == nullptr) {
    result->Error("invalid_args", "A valid argument map is required.");
    return;
  }

  int64_t view_id = 0;
  if (!ReadInt64(*arguments, "viewId", &view_id)) {
    result->Error("invalid_args", "A valid viewId is required.");
    return;
  }

  if (method_call.method_name() == "dispose") {
    DisposePlayer(view_id);
    result->Success();
    return;
  }

  WindowsVlcPlayer *player = FindPlayer(*arguments, result.get());
  if (player == nullptr) {
    return;
  }

  std::string error;
  if (method_call.method_name() == "setSource") {
    error = player->SetSource(ReadString(*arguments, "uri"),
                              ReadHeaders(*arguments),
                              ReadBool(*arguments, "autoPlay"));
    if (error == "A non-empty uri is required.") {
      result->Error("invalid_args", error);
      return;
    }
  } else if (method_call.method_name() == "play") {
    error = player->Play();
  } else if (method_call.method_name() == "pause") {
    error = player->Pause();
  } else if (method_call.method_name() == "stop") {
    error = player->Stop();
  } else if (method_call.method_name() == "seekTo") {
    int64_t position = 0;
    if (!ReadInt64(*arguments, "position", &position) || position < 0) {
      result->Error("invalid_args", "A non-negative position is required.");
      return;
    }
    error = player->SeekTo(position);
  } else if (method_call.method_name() == "setVolume") {
    int64_t volume = 0;
    if (!ReadInt64(*arguments, "volume", &volume)) {
      result->Error("invalid_args", "A volume value is required.");
      return;
    }
    error = player->SetVolume(static_cast<int>(volume));
  } else if (method_call.method_name() == "setPlaybackSpeed") {
    double speed = 0;
    if (!ReadDouble(*arguments, "speed", &speed) || speed <= 0) {
      result->Error("invalid_args", "A positive playback speed is required.");
      return;
    }
    error = player->SetPlaybackSpeed(speed);
  } else {
    result->NotImplemented();
    return;
  }

  if (!error.empty()) {
    result->Error("vlc_error", error);
    return;
  }
  result->Success();
}

WindowsVlcPlayer *VlcPlayerPlugin::FindPlayer(
    const EncodableMap &arguments,
    flutter::MethodResult<EncodableValue> *result) {
  int64_t view_id = 0;
  if (!ReadInt64(arguments, "viewId", &view_id)) {
    result->Error("invalid_args", "A valid viewId is required.");
    return nullptr;
  }

  auto it = players_.find(view_id);
  if (it == players_.end()) {
    result->Error("player_not_found",
                  "No vlc_player player exists for viewId " +
                      std::to_string(view_id) + ".");
    return nullptr;
  }
  return it->second.get();
}

void VlcPlayerPlugin::DisposePlayer(int64_t view_id) {
  auto it = players_.find(view_id);
  if (it != players_.end()) {
    players_.erase(it);
  }
}

}  // namespace vlc_player
