#ifndef VLC_PLAYER_NATIVE_DART_PORT_H_
#define VLC_PLAYER_NATIVE_DART_PORT_H_

#include <dart_native_api.h>

namespace vlc_player {

using PostCObject = decltype(&Dart_PostCObject);

struct DartPort {
  int64_t id = 0;
  PostCObject post = nullptr;

  explicit operator bool() const { return id != 0 && post != nullptr; }

  // Dart copies ordinary typed data during the call. The sender keeps ownership.
  void Send(const uint8_t* bytes, intptr_t size) const {
    Dart_CObject message = {};
    message.type = Dart_CObject_kTypedData;
    message.value.as_typed_data.type = Dart_TypedData_kUint8;
    message.value.as_typed_data.length = size;
    message.value.as_typed_data.values = bytes;
    if (*this) post(id, &message);
  }
};

}  // namespace vlc_player

#endif  // VLC_PLAYER_NATIVE_DART_PORT_H_
