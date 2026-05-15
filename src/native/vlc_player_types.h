#ifndef VLC_PLAYER_NATIVE_VLC_PLAYER_TYPES_H_
#define VLC_PLAYER_NATIVE_VLC_PLAYER_TYPES_H_

#include <cstdint>
#include <string>
#include <vector>

namespace vlc_player {

struct VlcTrackDescription {
  int id = -1;
  std::string name;
  std::string language;
};

struct VlcMediaTrackInfo {
  std::string type = "unknown";
  std::string codec;
  std::string language;
  int64_t bitrate = 0;
  int64_t width = 0;
  int64_t height = 0;
  int64_t channels = 0;
  int64_t sample_rate = 0;
};

struct VlcMediaInfo {
  std::string title;
  std::string artist;
  std::string album;
  int64_t duration = 0;
  std::vector<VlcMediaTrackInfo> video_tracks;
  std::vector<VlcMediaTrackInfo> audio_tracks;
  std::vector<VlcMediaTrackInfo> subtitle_tracks;
};

struct VlcSnapshot {
  std::string state = "idle";
  int64_t position = 0;
  int64_t duration = 0;
  int volume = 100;
  double playback_speed = 1.0;
  std::string error_description;
};

}  // namespace vlc_player

#endif  // VLC_PLAYER_NATIVE_VLC_PLAYER_TYPES_H_
