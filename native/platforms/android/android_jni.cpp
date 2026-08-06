#include <jni.h>
#include <jni/jni.hpp>

#include "jni.hpp"

namespace mbgl {
namespace android {

void RegisterNativeHTTPRequest(jni::JNIEnv&);

} // namespace android
} // namespace mbgl

extern "C" JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM* vm, void*) {
    if (!vm) {
        return JNI_ERR;
    }

    mbgl::android::theJVM = vm;
    auto& env = jni::GetEnv(*vm, jni::jni_version_1_6);
    mbgl::android::RegisterNativeHTTPRequest(env);
    return JNI_VERSION_1_6;
}
