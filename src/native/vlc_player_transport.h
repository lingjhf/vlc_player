#ifndef VLC_PLAYER_NATIVE_TRANSPORT_H_
#define VLC_PLAYER_NATIVE_TRANSPORT_H_

#include <stdint.h>

#if defined(_WIN32) && defined(FLUTTER_PLUGIN_IMPL)
#define VLC_TRANSPORT_EXPORT __declspec(dllexport)
#elif defined(__ANDROID__)
#define VLC_TRANSPORT_EXPORT __attribute__((visibility("default")))
#else
#define VLC_TRANSPORT_EXPORT
#endif

#ifdef __cplusplus
extern "C" {
#endif

// The platform copies the request before returning. Replies are encoded with
// Flutter's standard method codec and posted to the supplied Dart native port.
VLC_TRANSPORT_EXPORT int32_t vlc_player_dispatch(
    int64_t engine_id, int64_t reply_port, void* post_c_object,
    const uint8_t* request, intptr_t size);

#ifdef __cplusplus
}
#endif

#endif  // VLC_PLAYER_NATIVE_TRANSPORT_H_
