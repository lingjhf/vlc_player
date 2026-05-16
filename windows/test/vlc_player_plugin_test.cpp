#include <flutter/method_call.h>
#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>
#include <gtest/gtest.h>
#include <windows.h>

#include <cstdint>
#include <limits>
#include <memory>
#include <string>
#include <variant>

#include "vlc_player_core.h"
#include "vlc_player_plugin.h"

namespace vlc_player {
namespace test {

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;
using flutter::MethodCall;
using flutter::MethodResultFunctions;

}  // namespace

TEST(VlcPlayerPlugin, MissingPlayerReturnsPlayerNotFound) {
  VlcPlayerPlugin plugin(nullptr, nullptr);

  std::string error_code;
  std::string error_message;
  EncodableMap arguments;
  arguments[EncodableValue("viewId")] = EncodableValue(int64_t{42});

  plugin.HandleMethodCall(
      MethodCall("play", std::make_unique<EncodableValue>(arguments)),
      std::make_unique<MethodResultFunctions<>>(
          nullptr,
          [&error_code, &error_message](const std::string &code,
                                        const std::string &message,
                                        const EncodableValue *details) {
            error_code = code;
            error_message = message;
          },
          nullptr));

  EXPECT_EQ(error_code, "player_not_found");
  EXPECT_NE(error_message.find("viewId 42"), std::string::npos);
}

TEST(VlcPlayerCore, SnapshotWithoutMediaIsIdle) {
  VlcPlayerCore core({}, [] {});

  ASSERT_TRUE(core.is_valid()) << core.error();
  const VlcSnapshot snapshot = core.Snapshot();

  EXPECT_EQ(snapshot.state, "idle");
  EXPECT_EQ(snapshot.position, 0);
  EXPECT_EQ(snapshot.duration, 0);
  EXPECT_EQ(snapshot.volume, 100);
}

TEST(VlcPlayerCore, RejectsEmptySourceUri) {
  VlcPlayerCore core({}, [] {});

  ASSERT_TRUE(core.is_valid()) << core.error();

  EXPECT_EQ(core.SetSource("", {}, {}, 0, false),
            "A non-empty uri is required.");
}

TEST(VlcPlayerCore, ClampsVolumeInSnapshot) {
  VlcPlayerCore core({}, [] {});

  ASSERT_TRUE(core.is_valid()) << core.error();

  EXPECT_EQ(core.SetVolume(250), "");
  EXPECT_EQ(core.Snapshot().volume, 200);

  EXPECT_EQ(core.SetVolume(-25), "");
  EXPECT_EQ(core.Snapshot().volume, 0);
}

TEST(VlcPlayerCore, RejectsInvalidPlaybackSpeeds) {
  VlcPlayerCore core({}, [] {});

  ASSERT_TRUE(core.is_valid()) << core.error();

  EXPECT_EQ(core.SetPlaybackSpeed(0),
            "A finite positive playback speed is required.");
  EXPECT_EQ(core.SetPlaybackSpeed(-1),
            "A finite positive playback speed is required.");
  EXPECT_EQ(core.SetPlaybackSpeed(std::numeric_limits<double>::infinity()),
            "A finite positive playback speed is required.");
}

TEST(VlcPlayerCore, CopyPixelsWithoutFrameReturnsFalse) {
  VlcPlayerCore core({}, [] {});
  const uint8_t sentinel = 0;
  const uint8_t *buffer = &sentinel;
  uint32_t width = 7;
  uint32_t height = 9;

  ASSERT_TRUE(core.is_valid()) << core.error();

  EXPECT_FALSE(core.CopyPixels(&buffer, &width, &height));
  EXPECT_EQ(buffer, &sentinel);
  EXPECT_EQ(width, 7u);
  EXPECT_EQ(height, 9u);
}

TEST(VlcPlayerCore, DisposeIsIdempotentAndGuardsCommands) {
  VlcPlayerCore core({}, [] {});

  ASSERT_TRUE(core.is_valid()) << core.error();

  core.Dispose();
  core.Dispose();

  EXPECT_FALSE(core.is_valid());
  EXPECT_EQ(core.Play(), "The vlc_player has been disposed.");
  EXPECT_EQ(core.SetVolume(100), "The vlc_player has been disposed.");
  EXPECT_TRUE(core.GetAudioTracks().empty());
}

}  // namespace test
}  // namespace vlc_player
