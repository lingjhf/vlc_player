#ifndef FLUTTER_PLUGIN_VLC_PLAYER_WINDOWS_PLAYER_TASK_RUNNER_H_
#define FLUTTER_PLUGIN_VLC_PLAYER_WINDOWS_PLAYER_TASK_RUNNER_H_

#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

#include <condition_variable>
#include <cstdint>
#include <functional>
#include <mutex>
#include <queue>
#include <string>
#include <system_error>
#include <thread>
#include <utility>

namespace vlc_player {

// The window belongs to Flutter's platform thread. Only VLC work runs on the
// single worker; player publication and Flutter channel changes run here.
class WindowsPlayerTaskRunner {
 public:
  WindowsPlayerTaskRunner() {
    class_name_ = L"VlcPlayerTaskRunner" +
                  std::to_wstring(reinterpret_cast<uintptr_t>(this));
    WNDCLASSW window_class = {};
    window_class.lpfnWndProc = WindowProc;
    window_class.hInstance = GetModuleHandleW(nullptr);
    window_class.lpszClassName = class_name_.c_str();
    if (!RegisterClassW(&window_class)) {
      return;
    }
    window_ =
        CreateWindowExW(0, class_name_.c_str(), L"", 0, 0, 0, 0, 0,
                        HWND_MESSAGE, nullptr, window_class.hInstance, this);
    if (window_ != nullptr) {
      try {
        worker_ = std::thread([this] { RunWorker(); });
      } catch (const std::system_error &) {
        DestroyWindow(window_);
        window_ = nullptr;
      }
    }
  }

  ~WindowsPlayerTaskRunner() {
    Shutdown();
    RunPlatformTasks();
    if (window_ != nullptr) {
      DestroyWindow(window_);
    }
    UnregisterClassW(class_name_.c_str(), GetModuleHandleW(nullptr));
  }

  bool is_valid() const { return window_ != nullptr; }

  void PostWorkerTask(std::function<void()> task) {
    {
      std::lock_guard<std::mutex> lock(worker_mutex_);
      worker_tasks_.push(std::move(task));
    }
    worker_condition_.notify_one();
  }

  void PostPlatformTask(std::function<void()> task) {
    std::lock_guard<std::mutex> lock(platform_mutex_);
    platform_tasks_.push(std::move(task));
    if (!platform_message_pending_) {
      platform_message_pending_ =
          PostMessageW(window_, kTaskMessage, 0, 0) != FALSE;
    }
  }

  void RunPlatformTasks() {
    std::queue<std::function<void()>> tasks;
    {
      std::lock_guard<std::mutex> lock(platform_mutex_);
      tasks.swap(platform_tasks_);
      platform_message_pending_ = false;
    }
    while (!tasks.empty()) {
      tasks.front()();
      tasks.pop();
    }
  }

  void Shutdown() {
    {
      std::lock_guard<std::mutex> lock(worker_mutex_);
      stopping_ = true;
    }
    worker_condition_.notify_one();
    if (worker_.joinable()) {
      worker_.join();
    }
  }

 private:
  static constexpr UINT kTaskMessage = WM_APP + 1;

  static LRESULT CALLBACK WindowProc(HWND window, UINT message, WPARAM wparam,
                                     LPARAM lparam) {
    if (message == WM_NCCREATE) {
      const auto *creation = reinterpret_cast<CREATESTRUCTW *>(lparam);
      SetWindowLongPtrW(window, GWLP_USERDATA,
                        reinterpret_cast<LONG_PTR>(creation->lpCreateParams));
    }
    auto *runner = reinterpret_cast<WindowsPlayerTaskRunner *>(
        GetWindowLongPtrW(window, GWLP_USERDATA));
    if (message == kTaskMessage && runner != nullptr) {
      runner->RunPlatformTasks();
      return 0;
    }
    return DefWindowProcW(window, message, wparam, lparam);
  }

  void RunWorker() {
    while (true) {
      std::function<void()> task;
      {
        std::unique_lock<std::mutex> lock(worker_mutex_);
        worker_condition_.wait(
            lock, [this] { return stopping_ || !worker_tasks_.empty(); });
        if (worker_tasks_.empty()) {
          return;
        }
        task = std::move(worker_tasks_.front());
        worker_tasks_.pop();
      }
      task();
    }
  }

  std::wstring class_name_;
  HWND window_ = nullptr;
  std::thread worker_;
  std::mutex worker_mutex_;
  std::condition_variable worker_condition_;
  std::queue<std::function<void()>> worker_tasks_;
  bool stopping_ = false;
  std::mutex platform_mutex_;
  std::queue<std::function<void()>> platform_tasks_;
  bool platform_message_pending_ = false;
};

}  // namespace vlc_player

#endif  // FLUTTER_PLUGIN_VLC_PLAYER_WINDOWS_PLAYER_TASK_RUNNER_H_