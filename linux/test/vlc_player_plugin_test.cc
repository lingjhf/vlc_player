#include <flutter_linux/flutter_linux.h>
#include <gmock/gmock.h>
#include <gtest/gtest.h>

#include "include/vlc_player/vlc_player_plugin.h"
#include "vlc_player_core.h"
#include "vlc_player_plugin_private.h"

// This demonstrates a simple unit test of the C portion of this plugin's
// implementation.
//
// Once you have built the plugin's example app, you can run these tests
// from the command line. For instance, for a plugin called my_plugin
// built for x64 debug, run:
// $ build/linux/x64/debug/plugins/my_plugin/my_plugin_test

namespace vlc_player {
namespace test {

TEST(VlcPlayerPlugin, GetPlatformVersion) {
  g_autoptr(FlMethodResponse) response = get_platform_version();
  ASSERT_NE(response, nullptr);
  ASSERT_TRUE(FL_IS_METHOD_SUCCESS_RESPONSE(response));
  FlValue* result = fl_method_success_response_get_result(
      FL_METHOD_SUCCESS_RESPONSE(response));
  ASSERT_EQ(fl_value_get_type(result), FL_VALUE_TYPE_STRING);
  // The full string varies, so just validate that it has the right format.
  EXPECT_THAT(fl_value_get_string(result), testing::StartsWith("Linux "));
}

TEST(VlcPlayerCore, SnapshotWithoutMediaIsIdle) {
  VlcPlayerCore core({"--aout=dummy"}, [] {});

  ASSERT_TRUE(core.is_valid()) << core.error();
  const VlcSnapshot snapshot = core.Snapshot();

  EXPECT_EQ(snapshot.state, "idle");
  EXPECT_EQ(snapshot.position, 0);
  EXPECT_EQ(snapshot.duration, 0);
  EXPECT_EQ(snapshot.volume, 100);
}

}  // namespace test
}  // namespace vlc_player
