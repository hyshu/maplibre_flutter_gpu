#include <jni.h>
#include <atomic>

#include "http_java_class.inc"

static std::atomic<int> responses{0};
static std::atomic<int> failures{0};
static std::atomic<int> sdkCalls{0};

static void gpuFailure(JNIEnv*, jobject, jint, jstring) { ++failures; }
static void sdkFailure(JNIEnv*, jobject, jint, jstring) { ++sdkCalls; }
static void gpuResponse(JNIEnv*, jobject, jint, jstring, jstring, jstring,
                        jstring, jstring, jstring, jbyteArray) {
    ++responses;
}
static void sdkResponse(JNIEnv*, jobject, jint, jstring, jstring, jstring,
                        jstring, jstring, jstring, jbyteArray) {
    ++sdkCalls;
}

static void registerCallbacks(JNIEnv* env, const char* className, bool gpu) {
    const auto type = env->FindClass(className);
    if (!type) return;
    if (!env->GetFieldID(type, "nativePtr", "J")) return;
    JNINativeMethod methods[] = {
        {const_cast<char*>("nativeOnFailure"),
         const_cast<char*>("(ILjava/lang/String;)V"),
         gpu ? reinterpret_cast<void*>(gpuFailure) : reinterpret_cast<void*>(sdkFailure)},
        {const_cast<char*>("nativeOnResponse"),
         const_cast<char*>("(ILjava/lang/String;Ljava/lang/String;Ljava/lang/String;"
                           "Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;[B)V"),
         gpu ? reinterpret_cast<void*>(gpuResponse) : reinterpret_cast<void*>(sdkResponse)},
    };
    env->RegisterNatives(type, methods, 2);
}

extern "C" JNIEXPORT void JNICALL Java_HttpCohosting_registerGpu(JNIEnv* env, jclass) {
    registerCallbacks(env, gpuJavaClass, true);
}
extern "C" JNIEXPORT void JNICALL Java_HttpCohosting_registerSdk(JNIEnv* env, jclass) {
    registerCallbacks(env, "org/maplibre/android/http/NativeHttpRequest", false);
}
extern "C" JNIEXPORT jint JNICALL Java_HttpCohosting_gpuResponses(JNIEnv*, jclass) {
    return responses.load();
}
extern "C" JNIEXPORT jint JNICALL Java_HttpCohosting_gpuFailures(JNIEnv*, jclass) {
    return failures.load();
}
extern "C" JNIEXPORT jint JNICALL Java_HttpCohosting_sdkCallbacks(JNIEnv*, jclass) {
    return sdkCalls.load();
}
