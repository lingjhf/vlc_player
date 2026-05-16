#ifndef VLC_PLAYER_TEST_NATIVE_VLC_PLAYER_CORE_TEST_SUITE_H_
#define VLC_PLAYER_TEST_NATIVE_VLC_PLAYER_CORE_TEST_SUITE_H_

#include <cstdint>
#include <limits>
#include <memory>
#include <string>
#include <vector>

#include <gtest/gtest.h>

#include "vlc_player_core.h"

namespace vlc_player {
namespace test {

std::vector<std::string> VlcPlayerCoreTestOptions();

namespace {

std::unique_ptr<VlcPlayerCore> MakeCore() {
  return std::make_unique<VlcPlayerCore>(VlcPlayerCoreTestOptions(), [] {});
}

}  // namespace

TEST(VlcPlayerCore, SnapshotWithoutMediaIsIdle) {
  auto core = MakeCore();

  ASSERT_TRUE(core->is_valid()) << core->error();
  const VlcSnapshot snapshot = core->Snapshot();

  EXPECT_EQ(snapshot.state, "idle");
  EXPECT_EQ(snapshot.position, 0);
  EXPECT_EQ(snapshot.duration, 0);
  EXPECT_EQ(snapshot.volume, 100);
}

TEST(VlcPlayerCore, RejectsEmptySourceUri) {
  auto core = MakeCore();

  ASSERT_TRUE(core->is_valid()) << core->error();

  EXPECT_EQ(core->SetSource("", {}, {}, 0, false),
            "A non-empty uri is required.");
}

TEST(VlcPlayerCore, ClampsVolumeInSnapshot) {
  auto core = MakeCore();

  ASSERT_TRUE(core->is_valid()) << core->error();

  EXPECT_EQ(core->SetVolume(250), "");
  EXPECT_EQ(core->Snapshot().volume, 200);

  EXPECT_EQ(core->SetVolume(-25), "");
  EXPECT_EQ(core->Snapshot().volume, 0);
}

TEST(VlcPlayerCore, RejectsInvalidPlaybackSpeeds) {
  auto core = MakeCore();

  ASSERT_TRUE(core->is_valid()) << core->error();

  EXPECT_EQ(core->SetPlaybackSpeed(0),
            "A finite positive playback speed is required.");
  EXPECT_EQ(core->SetPlaybackSpeed(-1),
            "A finite positive playback speed is required.");
  EXPECT_EQ(core->SetPlaybackSpeed(std::numeric_limits<double>::infinity()),
            "A finite positive playback speed is required.");
}

TEST(VlcPlayerCore, CopyPixelsWithoutFrameReturnsFalse) {
  auto core = MakeCore();
  const uint8_t sentinel = 0;
  const uint8_t* buffer = &sentinel;
  uint32_t width = 7;
  uint32_t height = 9;

  ASSERT_TRUE(core->is_valid()) << core->error();

  EXPECT_FALSE(core->CopyPixels(&buffer, &width, &height));
  EXPECT_EQ(buffer, &sentinel);
  EXPECT_EQ(width, 7u);
  EXPECT_EQ(height, 9u);
}

TEST(VlcPlayerCore, DisposeIsIdempotentAndGuardsCommands) {
  auto core = MakeCore();

  ASSERT_TRUE(core->is_valid()) << core->error();

  core->Dispose();
  core->Dispose();

  EXPECT_FALSE(core->is_valid());
  EXPECT_EQ(core->Play(), "The vlc_player has been disposed.");
  EXPECT_EQ(core->SetVolume(100), "The vlc_player has been disposed.");
  EXPECT_TRUE(core->GetAudioTracks().empty());
}

}  // namespace test
}  // namespace vlc_player

#endif  // VLC_PLAYER_TEST_NATIVE_VLC_PLAYER_CORE_TEST_SUITE_H_
