package dev.maplibre.fluttergpu;

import android.content.Context;

import androidx.annotation.NonNull;

import java.io.File;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/** Loads the FFI bridge through the JVM so JNI_OnLoad receives Android's JavaVM. */
public final class MaplibreFlutterGpuPlugin
    implements FlutterPlugin, MethodChannel.MethodCallHandler {
  private static final String CHANNEL = "dev.maplibre.fluttergpu/native_sessions";

  private MethodChannel channel;
  private Context applicationContext;
  private File sourceLibrary;
  private boolean libraryLoaded;

  @Override
  public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
    applicationContext = binding.getApplicationContext();
    sourceLibrary =
        new File(applicationContext.getApplicationInfo().nativeLibraryDir,
            "libmaplibre_bridge.so");
    channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL);
    channel.setMethodCallHandler(this);
  }

  @Override
  public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
    if (channel != null) {
      channel.setMethodCallHandler(null);
      channel = null;
    }
    applicationContext = null;
  }

  @Override
  public synchronized void onMethodCall(
      @NonNull MethodCall call, @NonNull MethodChannel.Result result) {
    switch (call.method) {
      case "acquire":
        try {
          result.success(acquireLibrary());
        } catch (UnsatisfiedLinkError error) {
          result.error("native_session", error.getMessage(), null);
        }
        break;
      case "release":
        // Native MapSession release handles per-map lifetime. The single DSO
        // and shared runtime remain process-owned.
        result.success(null);
        break;
      default:
        result.notImplemented();
    }
  }

  private String acquireLibrary() {
    if (!libraryLoaded) {
      System.loadLibrary("maplibre_bridge");
      libraryLoaded = true;
    }
    // DynamicLibrary.open reuses the already loaded process image. Returning
    // the packaged absolute path keeps lookup deterministic when extracted
    // native libraries are enabled; the soname covers direct-from-APK mode.
    if (sourceLibrary != null && sourceLibrary.isFile()) {
      return sourceLibrary.getAbsolutePath();
    }
    return "libmaplibre_bridge.so";
  }
}
