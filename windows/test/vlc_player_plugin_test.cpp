#include <flutter/method_call.h>
#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>
#include <gtest/gtest.h>
#include <windows.h>

#include <cstdint>
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

}  // namespace test
}  // namespace vlc_player
