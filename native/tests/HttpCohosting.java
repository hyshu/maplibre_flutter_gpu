import java.io.ByteArrayInputStream;
import java.io.InputStream;
import java.lang.reflect.Constructor;
import java.net.HttpURLConnection;
import java.net.URL;
import java.net.URLConnection;
import java.net.URLStreamHandler;
import org.maplibre.android.http.SdkState;

public final class HttpCohosting {
  private static native void registerGpu();
  private static native void registerSdk();
  private static native int gpuResponses();
  private static native int gpuFailures();
  private static native int sdkCallbacks();

  private static Object startGpuRequest() throws Exception {
    Class<?> type = Class.forName("dev.maplibre.fluttergpu.NativeHttpRequest");
    Constructor<?> constructor = type.getDeclaredConstructor(
        long.class, String.class, String.class, String.class, String.class, boolean.class);
    constructor.setAccessible(true);
    return constructor.newInstance(1L, "http://fixture.invalid/tile", "", "", "", false);
  }

  private static void awaitResponses(int expected) throws Exception {
    long deadline = System.nanoTime() + 5_000_000_000L;
    while (gpuResponses() < expected && System.nanoTime() < deadline) {
      Thread.sleep(1);
    }
    if (gpuResponses() != expected || gpuFailures() != 0) {
      throw new AssertionError("GPU request did not reach its own native callback");
    }
  }

  public static void main(String[] arguments) throws Exception {
    System.load(arguments[0]);
    URL.setURLStreamHandlerFactory(protocol -> protocol.equals("http") ? new URLStreamHandler() {
      protected URLConnection openConnection(URL url) {
        return new HttpURLConnection(url) {
          public void connect() {}
          public boolean usingProxy() { return false; }
          public void disconnect() {}
          public int getResponseCode() { return 200; }
          public InputStream getInputStream() {
            return new ByteArrayInputStream(new byte[] {1, 2, 3});
          }
        };
      }
    } : null);

    boolean gpuFirst = arguments[1].equals("gpu-first");
    org.maplibre.android.http.NativeHttpRequest sdk = null;
    if (!gpuFirst) {
      SdkState.initialized = true;
      registerSdk();
      sdk = new org.maplibre.android.http.NativeHttpRequest();
      sdk.emitCallback();
    }
    registerGpu();
    Object first = startGpuRequest();
    awaitResponses(1);
    first.getClass().getMethod("cancel").invoke(first);
    if (gpuFirst) {
      if (SdkState.initialized) throw new AssertionError("GPU initialized the SDK");
      SdkState.initialized = true;
      registerSdk();
      sdk = new org.maplibre.android.http.NativeHttpRequest();
    }
    sdk.emitCallback();
    Object second = startGpuRequest();
    awaitResponses(2);
    second.getClass().getMethod("cancel").invoke(second);
    int expectedSdkCallbacks = gpuFirst ? 1 : 2;
    if (sdkCallbacks() != expectedSdkCallbacks) {
      throw new AssertionError("One library replaced another library's native callbacks");
    }
    System.out.println(arguments[1] + " HTTP initialization and JNI callback isolation passed");
  }
}
