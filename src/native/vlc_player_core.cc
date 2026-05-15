#include "vlc_player_core.h"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <exception>
#include <sstream>
#include <utility>

namespace vlc_player {
namespace {

int64_t NonNegative(libvlc_time_t value) {
  return std::max<int64_t>(0, value);
}

}  // namespace

VlcPlayerCore::VlcPlayerCore(std::vector<std::string> options,
                             FrameAvailableCallback on_frame_available)
    : on_frame_available_(std::move(on_frame_available)) {
  std::vector<const char*> argv;
  argv.reserve(options.size());
  for (const auto& option : options) {
    argv.push_back(option.c_str());
  }

  try {
    instance_ =
        std::make_unique<VLC::Instance>(static_cast<int>(argv.size()),
                                        argv.data());
    player_ = std::make_unique<VLC::MediaPlayer>(*instance_);
  } catch (const std::exception& error) {
    init_error_ = error.what();
    return;
  }

  player_->setVideoCallbacks(
      [this](void** planes) -> void* { return Lock(planes); },
      [this](void* picture, void* const* planes) { Unlock(picture, planes); },
      [this](void* picture) { Display(picture); });
  player_->setVideoFormatCallbacks(
      [this](char* chroma, uint32_t* width, uint32_t* height,
             uint32_t* pitches, uint32_t* lines) -> uint32_t {
        return SetupFormat(chroma, width, height, pitches, lines);
      },
      []() {});
}

VlcPlayerCore::~VlcPlayerCore() {
  Dispose();
}

bool VlcPlayerCore::is_valid() const {
  return init_error_.empty() && player_ != nullptr;
}

const std::string& VlcPlayerCore::error() const {
  return init_error_;
}

std::string VlcPlayerCore::SetSource(const std::string& uri,
                                     const std::vector<std::string>& headers,
                                     const std::vector<std::string>&
                                         media_options,
                                     int64_t start_position,
                                     bool auto_play) {
  if (const auto error = ActiveError(); !error.empty()) {
    return error;
  }
  if (uri.empty()) {
    return "A non-empty uri is required.";
  }

  try {
    VLC::Media media(*instance_, uri, VLC::Media::FromLocation);
    for (const auto& header : headers) {
      media.addOption(header);
    }
    for (const auto& option : media_options) {
      media.addOption(option);
    }
    if (start_position > 0) {
      std::ostringstream option;
      option << ":start-time=" << (static_cast<double>(start_position) / 1000);
      media.addOption(option.str());
    }
    player_->setMedia(media);
  } catch (const std::exception&) {
    return "Unable to create VLC media.";
  }

  {
    std::lock_guard<std::mutex> lock(state_mutex_);
    state_override_ = "opening";
    error_code_.clear();
    error_description_.clear();
  }

  return auto_play ? Play() : "";
}

std::string VlcPlayerCore::Play() {
  if (const auto error = ActiveError(); !error.empty()) {
    return error;
  }
  if (!player_->play()) {
    return "VLC failed to start playback.";
  }
  {
    std::lock_guard<std::mutex> lock(state_mutex_);
    state_override_.clear();
  }
  return "";
}

std::string VlcPlayerCore::Pause() {
  if (const auto error = ActiveError(); !error.empty()) {
    return error;
  }
  player_->pause();
  {
    std::lock_guard<std::mutex> lock(state_mutex_);
    state_override_.clear();
  }
  return "";
}

std::string VlcPlayerCore::Stop() {
  if (const auto error = ActiveError(); !error.empty()) {
    return error;
  }
  player_->stop();
  {
    std::lock_guard<std::mutex> lock(state_mutex_);
    state_override_ = "stopped";
  }
  return "";
}

std::string VlcPlayerCore::SeekTo(int64_t milliseconds) {
  if (const auto error = ActiveError(); !error.empty()) {
    return error;
  }
  player_->setTime(std::max<int64_t>(0, milliseconds));
  return "";
}

std::string VlcPlayerCore::SetVolume(int volume) {
  if (const auto error = ActiveError(); !error.empty()) {
    return error;
  }
  const int normalized_volume = std::clamp(volume, 0, 200);
  {
    std::lock_guard<std::mutex> lock(state_mutex_);
    volume_ = normalized_volume;
  }
  player_->setVolume(normalized_volume);
  return "";
}

std::string VlcPlayerCore::SetPlaybackSpeed(double speed) {
  if (const auto error = ActiveError(); !error.empty()) {
    return error;
  }
  if (!std::isfinite(speed) || speed <= 0) {
    return "A finite positive playback speed is required.";
  }
  player_->setRate(static_cast<float>(speed));
  return "";
}

std::vector<VlcTrackDescription> VlcPlayerCore::GetAudioTracks() {
  if (!is_valid()) {
    return {};
  }
  return TrackDescriptions(player_->audioTrackDescription());
}

std::string VlcPlayerCore::SetAudioTrack(int id) {
  if (const auto error = ActiveError(); !error.empty()) {
    return error;
  }
  if (!player_->setAudioTrack(id)) {
    return "Audio track " + std::to_string(id) + " was not found.";
  }
  return "";
}

std::vector<VlcTrackDescription> VlcPlayerCore::GetSubtitleTracks() {
  if (!is_valid()) {
    return {};
  }
  return TrackDescriptions(player_->spuDescription());
}

std::string VlcPlayerCore::SetSubtitleTrack(int id) {
  if (const auto error = ActiveError(); !error.empty()) {
    return error;
  }
  if (player_->setSpu(id) != 0) {
    return "Subtitle track " + std::to_string(id) + " was not found.";
  }
  return "";
}

std::string VlcPlayerCore::DisableSubtitle() {
  if (const auto error = ActiveError(); !error.empty()) {
    return error;
  }
  player_->setSpu(-1);
  return "";
}

std::string VlcPlayerCore::AddSubtitle(const std::string& uri) {
  if (const auto error = ActiveError(); !error.empty()) {
    return error;
  }
  if (uri.empty()) {
    return "A non-empty subtitle uri is required.";
  }
  if (!player_->addSlave(VLC::MediaSlave::Type::Subtitle, uri, true)) {
    return "Failed to add subtitle: " + uri;
  }
  return "";
}

VlcMediaInfo VlcPlayerCore::GetMediaInfo() {
  VlcMediaInfo info;
  if (!is_valid()) {
    return info;
  }

  info.duration = NonNegative(player_->length());
  auto media = player_->media();
  if (media == nullptr) {
    return info;
  }

  info.title = media->meta(libvlc_meta_Title);
  info.artist = media->meta(libvlc_meta_Artist);
  info.album = media->meta(libvlc_meta_Album);

  for (const auto& track : media->tracks()) {
    auto track_info = MediaTrackInfo(track);
    switch (track.type()) {
      case VLC::MediaTrack::Type::Audio:
        info.audio_tracks.push_back(std::move(track_info));
        break;
      case VLC::MediaTrack::Type::Video:
        info.video_tracks.push_back(std::move(track_info));
        break;
      case VLC::MediaTrack::Type::Subtitle:
        info.subtitle_tracks.push_back(std::move(track_info));
        break;
      default:
        break;
    }
  }
  return info;
}

VlcSnapshot VlcPlayerCore::Snapshot() {
  VlcSnapshot snapshot;
  if (!is_valid()) {
    std::lock_guard<std::mutex> lock(state_mutex_);
    snapshot.volume = volume_;
    if (!error_description_.empty()) {
      snapshot.error_code =
          error_code_.empty() ? "create_failed" : error_code_;
    }
    snapshot.error_description = error_description_;
    return snapshot;
  }

  const libvlc_state_t state = player_->state();
  {
    std::lock_guard<std::mutex> lock(state_mutex_);
    if (state == libvlc_Error) {
      error_code_ = "playback_error";
      error_description_ = "VLC encountered an error while playing the media.";
    }
    snapshot.state = state_override_.empty() ? StateName(state) : state_override_;
    snapshot.volume = volume_;
    snapshot.error_code = error_code_;
    snapshot.error_description = error_description_;
  }
  snapshot.position = NonNegative(player_->time());
  snapshot.duration = NonNegative(player_->length());
  snapshot.playback_speed = static_cast<double>(player_->rate());
  snapshot.is_ready = IsReadyState(snapshot.state);
  snapshot.is_seekable = player_->isSeekable();
  snapshot.is_live = IsLiveState(snapshot.state) && snapshot.duration == 0 &&
                     !snapshot.is_seekable;
  {
    std::lock_guard<std::mutex> lock(video_mutex_);
    snapshot.video_width = video_width_;
    snapshot.video_height = video_height_;
  }
  return snapshot;
}

bool VlcPlayerCore::CopyPixels(const uint8_t** out_buffer,
                               uint32_t* width,
                               uint32_t* height) {
  std::lock_guard<std::mutex> lock(video_mutex_);
  if (render_buffer_.empty()) {
    return false;
  }
  texture_buffer_ = render_buffer_;
  *out_buffer = texture_buffer_.data();
  *width = video_width_;
  *height = video_height_;
  return true;
}

void VlcPlayerCore::Dispose() {
  if (disposed_.exchange(true)) {
    return;
  }
  if (player_ != nullptr) {
    libvlc_video_set_callbacks(player_->get(), nullptr, nullptr, nullptr,
                               nullptr);
    libvlc_video_set_format_callbacks(player_->get(), nullptr, nullptr);
    player_->stop();
    player_.reset();
  }
  on_frame_available_ = nullptr;
  instance_.reset();
}

uint32_t VlcPlayerCore::SetupFormat(char* chroma,
                                    uint32_t* width,
                                    uint32_t* height,
                                    uint32_t* pitches,
                                    uint32_t* lines) {
  std::memcpy(chroma, "RGBA", 4);
  pitches[0] = *width * 4;
  lines[0] = *height;
  ResizeVideoBuffer(*width, *height, pitches[0]);
  return 1;
}

void* VlcPlayerCore::Lock(void** planes) {
  video_mutex_.lock();
  if (frame_buffer_.empty()) {
    video_mutex_.unlock();
    planes[0] = nullptr;
    return nullptr;
  }
  planes[0] = frame_buffer_.data();
  return this;
}

void VlcPlayerCore::Unlock(void* picture, void* const* planes) {
  if (picture == nullptr) {
    return;
  }
  render_buffer_ = frame_buffer_;
  video_mutex_.unlock();
}

void VlcPlayerCore::Display(void* picture) {
  if (!disposed_.load() && on_frame_available_) {
    on_frame_available_();
  }
}

void VlcPlayerCore::ResizeVideoBuffer(uint32_t width,
                                      uint32_t height,
                                      uint32_t pitch) {
  std::lock_guard<std::mutex> lock(video_mutex_);
  video_width_ = width;
  video_height_ = height;
  frame_buffer_.assign(static_cast<size_t>(pitch) * height, 0);
  render_buffer_ = frame_buffer_;
  texture_buffer_ = frame_buffer_;
}

std::string VlcPlayerCore::ActiveError() const {
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

std::string VlcPlayerCore::StateName(libvlc_state_t state) {
  switch (state) {
    case libvlc_Opening:
      return "opening";
    case libvlc_Buffering:
      return "buffering";
    case libvlc_Playing:
      return "playing";
    case libvlc_Paused:
      return "paused";
    case libvlc_Stopped:
      return "stopped";
    case libvlc_Ended:
      return "ended";
    case libvlc_Error:
      return "error";
    default:
      return "idle";
  }
}

bool VlcPlayerCore::IsReadyState(const std::string& state) {
  return state == "playing" || state == "paused" || state == "stopped" ||
         state == "ended";
}

bool VlcPlayerCore::IsLiveState(const std::string& state) {
  return state == "buffering" || state == "playing" || state == "paused";
}

std::string VlcPlayerCore::FourCCString(uint32_t value) {
  char codec[5] = {
      static_cast<char>(value & 0xff),
      static_cast<char>((value >> 8) & 0xff),
      static_cast<char>((value >> 16) & 0xff),
      static_cast<char>((value >> 24) & 0xff),
      '\0',
  };
  for (int i = 0; i < 4; ++i) {
    if (codec[i] < 32 || codec[i] > 126) {
      return "";
    }
  }
  return codec;
}

std::string VlcPlayerCore::TrackTypeName(VLC::MediaTrack::Type type) {
  switch (type) {
    case VLC::MediaTrack::Type::Audio:
      return "audio";
    case VLC::MediaTrack::Type::Video:
      return "video";
    case VLC::MediaTrack::Type::Subtitle:
      return "subtitle";
    default:
      return "unknown";
  }
}

VlcMediaTrackInfo VlcPlayerCore::MediaTrackInfo(const VLC::MediaTrack& track) {
  VlcMediaTrackInfo info;
  info.type = TrackTypeName(track.type());
  info.codec = FourCCString(track.codec());
  info.language = track.language();
  info.bitrate = track.bitrate();
  if (track.type() == VLC::MediaTrack::Type::Video) {
    info.width = track.width();
    info.height = track.height();
  }
  if (track.type() == VLC::MediaTrack::Type::Audio) {
    info.channels = track.channels();
    info.sample_rate = track.rate();
  }
  return info;
}

std::vector<VlcTrackDescription> VlcPlayerCore::TrackDescriptions(
    const std::vector<VLC::TrackDescription>& tracks) {
  std::vector<VlcTrackDescription> result;
  result.reserve(tracks.size());
  for (const auto& track : tracks) {
    result.push_back(VlcTrackDescription{
        track.id(),
        track.name(),
        "",
    });
  }
  return result;
}

}  // namespace vlc_player
