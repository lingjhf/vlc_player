#include <flutter/binary_messenger.h>
#include <flutter/method_call.h>
#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>
#include <flutter/texture_registrar.h>
#include <gtest/gtest.h>
#include <windows.h>

#include <algorithm>
#include <atomic>
#include <cstdint>
#include <functional>
#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include "vlc_player_plugin.h"
#include "windows_player_task_runner.h"

namespace vlc_player {
namespace test {
namespace {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;

bool PumpUntil(const std::function<bool()>& ready) {
  const ULONGLONG deadline = GetTickCount64() + 60000;
  while (!ready() && GetTickCount64() < deadline) {
    MSG message;
    while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) {
      TranslateMessage(&message);
      DispatchMessageW(&message);
    }
    Sleep(1);
  }
  return ready();
}

class TestMessenger : public flutter::BinaryMessenger {
 public:
  void Send(const std::string&, const uint8_t*, size_t,
            flutter::BinaryReply) const override {
    if (std::this_thread::get_id() != platform_thread_) {
      ++off_platform_sends;
    }
    ++sent_events;
  }

  void SetMessageHandler(const std::string& channel,
                         flutter::BinaryMessageHandler handler) override {
    if (std::this_thread::get_id() != platform_thread_) {
      ++off_platform_updates;
    }
    active_handlers += handler ? 1 : -1;
    std::lock_guard<std::mutex> lock(handler_mutex_);
    if (handler) {
      handlers_[channel] = std::move(handler);
    } else {
      handlers_.erase(channel);
    }
  }

  void Listen(const std::string& channel) {
    const auto message =
        flutter::StandardMethodCodec::GetInstance().EncodeMethodCall(
            flutter::MethodCall<EncodableValue>("listen", nullptr));
    flutter::BinaryMessageHandler handler;
    {
      std::lock_guard<std::mutex> lock(handler_mutex_);
      handler = handlers_.at(channel);
    }
    handler(message->data(), message->size(), [](const uint8_t*, size_t) {});
  }

  std::atomic<int> off_platform_updates{0};
  std::atomic<int> active_handlers{0};
  mutable std::atomic<int> off_platform_sends{0};
  mutable std::atomic<int> sent_events{0};

 private:
  std::thread::id platform_thread_ = std::this_thread::get_id();
  std::mutex handler_mutex_;
  std::map<std::string, flutter::BinaryMessageHandler> handlers_;
};

class TestTextureRegistrar : public flutter::TextureRegistrar {
 public:
  int64_t RegisterTexture(flutter::TextureVariant* texture) override {
    std::lock_guard<std::mutex> lock(mutex_);
    const int64_t id = next_id_++;
    textures_[id] = texture;
    return id;
  }

  bool MarkTextureFrameAvailable(int64_t) override { return true; }

  bool UnregisterTexture(int64_t id) override {
    UnregisterTexture(id, nullptr);
    return true;
  }

  void UnregisterTexture(int64_t id, std::function<void()> callback) override {
    {
      std::lock_guard<std::mutex> lock(mutex_);
      retired_texture_ = textures_.at(id);
      textures_.erase(id);
      if (delay_unregister) {
        pending_callbacks_.push_back(std::move(callback));
      }
    }
    if (!delay_unregister && callback) {
      callback();
    }
    ++unregistered;
  }

  flutter::TextureVariant* retired_texture() {
    std::lock_guard<std::mutex> lock(mutex_);
    return retired_texture_;
  }

  void AcknowledgeUnregister() {
    std::vector<std::function<void()>> callbacks;
    {
      std::lock_guard<std::mutex> lock(mutex_);
      callbacks.swap(pending_callbacks_);
    }
    for (const auto& callback : callbacks) {
      if (callback) callback();
    }
  }

  bool delay_unregister = false;
  std::atomic<int> unregistered{0};

 private:
  std::mutex mutex_;
  int64_t next_id_ = 1;
  std::map<int64_t, flutter::TextureVariant*> textures_;
  std::vector<std::function<void()>> pending_callbacks_;
  flutter::TextureVariant* retired_texture_ = nullptr;
};

struct Result {
  bool done = false;
  std::string error;
  EncodableMap response;
};

std::shared_ptr<Result> Call(VlcPlayerPlugin& plugin, const std::string& method,
                             const EncodableMap& arguments) {
  auto result = std::make_shared<Result>();
  plugin.HandleMethodCall(
      flutter::MethodCall<EncodableValue>(
          method, std::make_unique<EncodableValue>(arguments)),
      std::make_unique<flutter::MethodResultFunctions<>>(
          [result](const EncodableValue* value) {
            if (value != nullptr) {
              if (const auto* map = std::get_if<EncodableMap>(value)) {
                result->response = *map;
              }
            }
            result->done = true;
          },
          [result](const std::string& code, const std::string&,
                   const EncodableValue*) {
            result->error = code;
            result->done = true;
          },
          [result] {
            result->error = "not_implemented";
            result->done = true;
          }));
  return result;
}

EncodableMap CreateArguments(bool invalid = false) {
  return {{EncodableValue("options"),
           EncodableValue(EncodableList{EncodableValue(
               invalid ? "--vlc-player-test-invalid-option" : "--no-audio")})}};
}

EncodableMap ViewArguments(int64_t view_id) {
  return {{EncodableValue("viewId"), EncodableValue(view_id)}};
}

// Count thread handles specifically so libVLC caches and unrelated file handles
// cannot hide or falsely report completed std::thread handles accumulating.
int ThreadHandleCount() {
  struct Entry {
    HANDLE handle;
    ULONG_PTR handle_count;
    ULONG_PTR pointer_count;
    ULONG granted_access;
    ULONG object_type;
    ULONG attributes;
    ULONG reserved;
  };
  struct Snapshot {
    ULONG_PTR count;
    ULONG_PTR reserved;
    Entry entries[1];
  };
  using Query = LONG(NTAPI*)(HANDLE, ULONG, void*, ULONG, ULONG*);
  auto query = reinterpret_cast<Query>(GetProcAddress(
      GetModuleHandleW(L"ntdll.dll"), "NtQueryInformationProcess"));
  if (!query) return -1;
  std::vector<uint8_t> storage(4096);
  LONG status;
  ULONG required = 0;
  do {
    status = query(GetCurrentProcess(), 51, storage.data(),
                   static_cast<ULONG>(storage.size()), &required);
    if (status == static_cast<LONG>(0xC0000004)) {
      storage.resize(
          (std::max)(storage.size() * 2, static_cast<size_t>(required)));
    }
  } while (status == static_cast<LONG>(0xC0000004));
  if (status < 0) return -1;
  auto* snapshot = reinterpret_cast<Snapshot*>(storage.data());
  int count = 0;
  for (ULONG_PTR index = 0; index < snapshot->count; ++index) {
    if (GetThreadId(snapshot->entries[index].handle) != 0) ++count;
  }
  return count;
}

TEST(VlcPlayerLifecycle, FailedCreateDetachesOnPlatformThread) {
  TestMessenger messenger;
  TestTextureRegistrar registrar;
  VlcPlayerPlugin plugin(&messenger, &registrar);
  auto result = Call(plugin, "create", CreateArguments(true));
  EXPECT_FALSE(result->done);
  ASSERT_TRUE(PumpUntil([&] { return result->done; }));
  EXPECT_EQ(result->error, "create_failed");
  ASSERT_TRUE(PumpUntil([&] { return registrar.unregistered == 1; }));
  EXPECT_EQ(messenger.off_platform_updates, 0);
  EXPECT_EQ(messenger.active_handlers, 0);
}

TEST(VlcPlayerLifecycle, RepeatedFailedCreatesReleaseFlutterResources) {
  TestMessenger messenger;
  TestTextureRegistrar registrar;
  VlcPlayerPlugin plugin(&messenger, &registrar);
  auto warmup = Call(plugin, "create", CreateArguments(true));
  ASSERT_TRUE(PumpUntil([&] { return warmup->done; }));
  ASSERT_EQ(warmup->error, "create_failed");
  ASSERT_TRUE(PumpUntil([&] { return registrar.unregistered == 1; }));
  for (int index = 0; index < 16; ++index) {
    auto result = Call(plugin, "create", CreateArguments(true));
    ASSERT_TRUE(PumpUntil([&] { return result->done; }));
    ASSERT_EQ(result->error, "create_failed");
    ASSERT_TRUE(PumpUntil([&] { return registrar.unregistered == index + 2; }));
  }
  EXPECT_EQ(messenger.off_platform_updates, 0);
  EXPECT_EQ(messenger.active_handlers, 0);
}

TEST(VlcPlayerLifecycle, DisposeDuringCreateCompletesWithoutPublishingPlayer) {
  TestMessenger messenger;
  TestTextureRegistrar registrar;
  VlcPlayerPlugin plugin(&messenger, &registrar);
  auto creation = Call(plugin, "create", CreateArguments());
  EXPECT_FALSE(creation->done);
  auto disposal = Call(plugin, "dispose", ViewArguments(1));
  EXPECT_TRUE(disposal->done);
  ASSERT_TRUE(PumpUntil([&] { return creation->done; }));
  EXPECT_EQ(creation->error, "player_not_found");
  ASSERT_TRUE(PumpUntil([&] { return registrar.unregistered == 1; }));
  EXPECT_EQ(messenger.off_platform_updates, 0);
  EXPECT_EQ(messenger.active_handlers, 0);
}

TEST(VlcPlayerLifecycle, RepeatedSuccessfulCreateAndDisposeReleasesResources) {
  TestMessenger messenger;
  TestTextureRegistrar registrar;
  VlcPlayerPlugin plugin(&messenger, &registrar);
  auto warmup = Call(plugin, "create", CreateArguments());
  ASSERT_TRUE(PumpUntil([&] { return warmup->done; }));
  ASSERT_TRUE(warmup->error.empty()) << warmup->error;
  Call(plugin, "dispose", ViewArguments(1));
  ASSERT_TRUE(PumpUntil([&] { return registrar.unregistered == 1; }));
  for (int index = 0; index < 8; ++index) {
    auto creation = Call(plugin, "create", CreateArguments());
    EXPECT_FALSE(creation->done);
    ASSERT_TRUE(PumpUntil([&] { return creation->done; }));
    ASSERT_TRUE(creation->error.empty()) << creation->error;
    const int64_t id =
        std::get<int64_t>(creation->response.at(EncodableValue("viewId")));
    auto disposal = Call(plugin, "dispose", ViewArguments(id));
    EXPECT_TRUE(disposal->done);
    ASSERT_TRUE(PumpUntil([&] { return registrar.unregistered == index + 2; }));
  }
  EXPECT_EQ(messenger.off_platform_updates, 0);
  EXPECT_EQ(messenger.active_handlers, 0);
}

TEST(VlcPlayerLifecycle, TextureCallbackSurvivesAsynchronousUnregister) {
  TestMessenger messenger;
  TestTextureRegistrar registrar;
  registrar.delay_unregister = true;
  VlcPlayerPlugin plugin(&messenger, &registrar);
  auto creation = Call(plugin, "create", CreateArguments());
  ASSERT_TRUE(PumpUntil([&] { return creation->done; }));
  ASSERT_TRUE(creation->error.empty()) << creation->error;
  Call(plugin, "dispose", ViewArguments(1));
  ASSERT_TRUE(PumpUntil([&] { return registrar.unregistered == 1; }));
  auto* retired = registrar.retired_texture();
  // Completing another initialization fences the preceding worker teardown.
  auto next = Call(plugin, "create", CreateArguments(true));
  ASSERT_TRUE(PumpUntil([&] { return next->done; }));
  ASSERT_EQ(next->error, "create_failed");
  ASSERT_NE(retired, nullptr);
  EXPECT_EQ(
      std::get<flutter::PixelBufferTexture>(*retired).CopyPixelBuffer(320, 180),
      nullptr);
  registrar.AcknowledgeUnregister();
}

TEST(VlcPlayerLifecycle, ShutdownDrainsPendingCreateOnPlatformThread) {
  TestMessenger messenger;
  TestTextureRegistrar registrar;
  auto plugin = std::make_unique<VlcPlayerPlugin>(&messenger, &registrar);
  auto creation = Call(*plugin, "create", CreateArguments());
  EXPECT_FALSE(creation->done);
  plugin.reset();
  EXPECT_TRUE(creation->done);
  EXPECT_EQ(creation->error, "player_not_found");
  EXPECT_EQ(registrar.unregistered, 1);
  EXPECT_EQ(messenger.off_platform_updates, 0);
  EXPECT_EQ(messenger.active_handlers, 0);
}

TEST(VlcPlayerLifecycle, PollingPlaybackEventsStayOnPlatformThread) {
  TestMessenger messenger;
  TestTextureRegistrar registrar;
  VlcPlayerPlugin plugin(&messenger, &registrar);
  auto creation = Call(plugin, "create", CreateArguments());
  ASSERT_TRUE(PumpUntil([&] { return creation->done; }));
  ASSERT_TRUE(creation->error.empty()) << creation->error;
  messenger.Listen("vlc_player/events/1");
  EncodableMap arguments = ViewArguments(1);
  arguments[EncodableValue("uri")] =
      EncodableValue(std::string("file:///") + VLC_PLAYER_TEST_MEDIA_PATH);
  arguments[EncodableValue("autoPlay")] = EncodableValue(true);
  auto source = Call(plugin, "setSource", arguments);
  ASSERT_TRUE(source->done);
  ASSERT_TRUE(source->error.empty()) << source->error;
  const int immediate_events = messenger.sent_events;
  ASSERT_TRUE(
      PumpUntil([&] { return messenger.sent_events > immediate_events; }));
  EXPECT_EQ(messenger.off_platform_sends, 0);
  Call(plugin, "dispose", ViewArguments(1));
  ASSERT_TRUE(PumpUntil([&] { return registrar.unregistered == 1; }));
  EXPECT_EQ(messenger.active_handlers, 0);
}

TEST(WindowsPlayerTaskRunner, ReusesAndReleasesWorkerThreadHandles) {
  const int before = ThreadHandleCount();
  ASSERT_GE(before, 0);
  {
    WindowsPlayerTaskRunner runner;
    ASSERT_TRUE(runner.is_valid());
    const auto platform_thread = std::this_thread::get_id();
    int completed = 0;
    auto enqueue = [&] {
      runner.PostWorkerTask([&] {
        EXPECT_NE(std::this_thread::get_id(), platform_thread);
        runner.PostPlatformTask([&] {
          EXPECT_EQ(std::this_thread::get_id(), platform_thread);
          ++completed;
        });
      });
    };
    enqueue();
    ASSERT_TRUE(PumpUntil([&] { return completed == 1; }));
    const int with_worker = ThreadHandleCount();
    ASSERT_GE(with_worker, 0);
    for (int index = 0; index < 128; ++index) enqueue();
    ASSERT_TRUE(PumpUntil([&] { return completed == 129; }));
    EXPECT_EQ(ThreadHandleCount(), with_worker);
  }
  EXPECT_EQ(ThreadHandleCount(), before);
}

}  // namespace
}  // namespace test
}  // namespace vlc_player
