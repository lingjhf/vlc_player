#include <jni.h>

#include <atomic>

#include "vlc_dart_port.h"
#include "vlc_player_transport.h"

namespace {

std::atomic<JavaVM*> java_vm{nullptr};
jclass transport_class = nullptr;
jmethodID enqueue_method = nullptr;

// A Dart isolate thread need not already be attached to the JVM.
class JniScope {
 public:
  explicit JniScope(JavaVM* vm) : vm_(vm) {
    const jint status =
        vm_->GetEnv(reinterpret_cast<void**>(&env_), JNI_VERSION_1_6);
    if (status == JNI_EDETACHED) {
      attached_ = vm_->AttachCurrentThread(&env_, nullptr) == JNI_OK;
      if (!attached_) env_ = nullptr;
    } else if (status != JNI_OK) {
      env_ = nullptr;
    }
  }

  ~JniScope() {
    if (attached_) vm_->DetachCurrentThread();
  }

  JNIEnv* env() const { return env_; }

 private:
  JavaVM* const vm_;
  JNIEnv* env_ = nullptr;
  bool attached_ = false;
};

}  // namespace

extern "C" JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM* vm, void*) {
  JNIEnv* env = nullptr;
  if (vm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6) != JNI_OK) {
    return JNI_ERR;
  }
  const jclass local_class =
      env->FindClass("com/lingjhf/vlc_player/VlcNativeTransport");
  if (local_class == nullptr) return JNI_ERR;
  enqueue_method = env->GetStaticMethodID(local_class, "enqueue", "(JJJ[B)Z");
  if (enqueue_method == nullptr) return JNI_ERR;
  transport_class = static_cast<jclass>(env->NewGlobalRef(local_class));
  if (transport_class == nullptr) return JNI_ERR;
  java_vm.store(vm, std::memory_order_release);
  return JNI_VERSION_1_6;
}

extern "C" JNIEXPORT void JNICALL JNI_OnUnload(JavaVM* vm, void*) {
  JNIEnv* env = nullptr;
  if (vm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6) == JNI_OK) {
    env->DeleteGlobalRef(transport_class);
  }
}

int32_t vlc_player_dispatch(int64_t engine_id, int64_t reply_port,
                            void* post_c_object, const uint8_t* request,
                            intptr_t size) {
  JavaVM* vm = java_vm.load(std::memory_order_acquire);
  if (!vm || !post_c_object || !request || size <= 0 || size > INT32_MAX) {
    return 0;
  }

  JniScope scope(vm);
  JNIEnv* env = scope.env();
  if (!env) return 0;
  const jsize length = static_cast<jsize>(size);
  jbyteArray bytes = env->NewByteArray(length);
  if (bytes == nullptr) {
    env->ExceptionClear();
    return 0;
  }
  env->SetByteArrayRegion(bytes, 0, length,
                          reinterpret_cast<const jbyte*>(request));
  if (env->ExceptionCheck()) {
    env->DeleteLocalRef(bytes);
    env->ExceptionClear();
    return 0;
  }
  const bool accepted = env->CallStaticBooleanMethod(
      transport_class, enqueue_method, static_cast<jlong>(engine_id),
      static_cast<jlong>(reply_port),
      static_cast<jlong>(reinterpret_cast<uintptr_t>(post_c_object)), bytes);
  env->DeleteLocalRef(bytes);
  if (env->ExceptionCheck()) {
    env->ExceptionClear();
    return 0;
  }
  return accepted ? 1 : 0;
}

extern "C" JNIEXPORT void JNICALL
Java_com_lingjhf_vlc_1player_VlcNativeTransport_post(JNIEnv* env, jclass,
                                                   jlong port, jlong callback,
                                                   jbyteArray bytes) {
  const jsize size = env->GetArrayLength(bytes);
  auto* data = size == 0 ? nullptr : env->GetByteArrayElements(bytes, nullptr);
  if (size != 0 && data == nullptr) return;
  const vlc_player::DartPort target{
      port, reinterpret_cast<vlc_player::PostCObject>(
                static_cast<uintptr_t>(callback))};
  target.Send(reinterpret_cast<const uint8_t*>(data), size);
  if (data != nullptr) env->ReleaseByteArrayElements(bytes, data, JNI_ABORT);
}
