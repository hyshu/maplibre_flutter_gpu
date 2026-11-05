package org.maplibre.android.http;

public final class NativeHttpRequest {
  static {
    if (!SdkState.initialized) {
      throw new IllegalStateException("SDK initialization is required");
    }
  }

  private long nativePtr = 1;

  public void emitCallback() {
    nativeOnFailure(0, "SDK callback");
  }

  private native void nativeOnFailure(int type, String message);
  private native void nativeOnResponse(
      int code, String etag, String modified, String cacheControl,
      String expires, String retryAfter, String rateLimitReset, byte[] body);
}
