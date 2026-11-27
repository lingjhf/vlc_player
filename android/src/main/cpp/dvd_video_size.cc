#include <dlfcn.h>
#include <jni.h>

#include <array>
#include <cstdint>
#include <memory>
#include <string>

namespace {

struct DvdNavigation;
constexpr int32_t kDvdnavSuccess = 1;
constexpr int32_t kTitleMenu = 2;
constexpr int32_t kRootMenu = 3;
constexpr size_t kDvdBlockSize = 2048;
constexpr int kMaxNavigationBlocks = 16;

template <typename Function>
Function Load(void* library, const char* name) {
  return reinterpret_cast<Function>(dlsym(library, name));
}

// libvlc-all bundles libdvdnav. Use its public API to read DVD geometry
// without accessing LibVLC's Java player internals.
jlong ReadDvdVideoSize(const char* path, int32_t title) {
  const std::unique_ptr<void, decltype(&dlclose)> library(
      dlopen("libvlc.so", RTLD_NOW | RTLD_LOCAL), dlclose);
  if (!library) return 0;

  using Open = int32_t (*)(DvdNavigation**, const char*);
  using Close = int32_t (*)(DvdNavigation*);
  using Select = int32_t (*)(DvdNavigation*, int32_t);
  using Read = int32_t (*)(DvdNavigation*, uint8_t*, int32_t*, int32_t*);
  using GetSize = int32_t (*)(DvdNavigation*, uint32_t*, uint32_t*);
  const auto open_dvd = Load<Open>(library.get(), "dvdnav_open");
  const auto close_dvd = Load<Close>(library.get(), "dvdnav_close");
  const auto play_title = Load<Select>(library.get(), "dvdnav_title_play");
  const auto open_menu = Load<Select>(library.get(), "dvdnav_menu_call");
  const auto read_block = Load<Read>(library.get(), "dvdnav_get_next_block");
  const auto get_size =
      Load<GetSize>(library.get(), "dvdnav_get_video_resolution");
  if (!open_dvd || !close_dvd || !play_title || !open_menu || !read_block ||
      !get_size) {
    return 0;
  }

  DvdNavigation* handle = nullptr;
  const int32_t opened = open_dvd(&handle, path);
  const std::unique_ptr<DvdNavigation, Close> dvd(handle, close_dvd);
  if (opened != kDvdnavSuccess || !dvd) return 0;
  if (title > 0) {
    if (play_title(dvd.get(), title) != kDvdnavSuccess) return 0;
  } else if (open_menu(dvd.get(), kTitleMenu) != kDvdnavSuccess) {
    open_menu(dvd.get(), kRootMenu);
  }

  std::array<uint8_t, kDvdBlockSize> block{};
  for (int attempt = 0; attempt <= kMaxNavigationBlocks; ++attempt) {
    uint32_t width = 0;
    uint32_t height = 0;
    // Releases of libdvdnav differ in their success return value.
    get_size(dvd.get(), &width, &height);
    if (width > 0 && height > 0 && width <= 720 && height <= 576) {
      return (static_cast<jlong>(width) << 32) | height;
    }
    int32_t event = 0;
    int32_t length = 0;
    if (attempt == kMaxNavigationBlocks ||
        read_block(dvd.get(), block.data(), &event, &length) != kDvdnavSuccess) {
      break;
    }
  }
  return 0;
}

}  // namespace

extern "C" JNIEXPORT jlong JNICALL
Java_com_lingjhf_vlc_1player_VlcNativeTransport_probeDvdVideoSize(
    JNIEnv* env, jclass, jbyteArray path, jint title) {
  const jsize length = env->GetArrayLength(path);
  if (length <= 0) return 0;
  std::string local_path(static_cast<size_t>(length), '\0');
  env->GetByteArrayRegion(path, 0, length,
                          reinterpret_cast<jbyte*>(local_path.data()));
  if (env->ExceptionCheck() || local_path.find('\0') != std::string::npos) {
    return 0;
  }
  return ReadDvdVideoSize(local_path.c_str(), title);
}
