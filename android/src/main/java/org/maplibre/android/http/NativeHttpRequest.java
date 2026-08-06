package org.maplibre.android.http;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.SocketTimeoutException;
import java.net.URL;
import java.net.UnknownHostException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.ThreadFactory;
import java.util.concurrent.atomic.AtomicInteger;

/**
 * Minimal Android HTTP adapter used by MapLibre Native's HTTPFileSource.
 *
 * <p>The class name, constructor, field, and native methods form a JNI ABI with
 * the vendored MapLibre Native Android implementation.
 */
public final class NativeHttpRequest {
  private static final int CONNECTION_ERROR = 0;
  private static final int TEMPORARY_ERROR = 1;

  private static final ExecutorService EXECUTOR =
      Executors.newCachedThreadPool(
          new ThreadFactory() {
            private final AtomicInteger nextId = new AtomicInteger();

            @Override
            public Thread newThread(Runnable runnable) {
              Thread thread =
                  new Thread(runnable, "MapLibreHttp-" + nextId.incrementAndGet());
              thread.setDaemon(true);
              return thread;
            }
          });

  @SuppressWarnings("unused")
  private long nativePtr;

  private volatile HttpURLConnection connection;
  private volatile boolean cancelled;

  @SuppressWarnings("unused")
  private NativeHttpRequest(
      long nativePtr,
      String resourceUrl,
      String dataRange,
      String etag,
      String modified,
      boolean offlineUsage) {
    this.nativePtr = nativePtr;
    EXECUTOR.execute(() -> execute(resourceUrl, dataRange, etag, modified));
  }

  @SuppressWarnings("unused")
  public void cancel() {
    HttpURLConnection activeConnection;
    synchronized (this) {
      cancelled = true;
      nativePtr = 0;
      activeConnection = connection;
    }
    if (activeConnection != null) {
      activeConnection.disconnect();
    }
  }

  private void execute(String resourceUrl, String dataRange, String etag, String modified) {
    HttpURLConnection request = null;
    try {
      request = (HttpURLConnection) new URL(resourceUrl).openConnection();
      connection = request;
      request.setConnectTimeout(15_000);
      request.setReadTimeout(30_000);
      request.setInstanceFollowRedirects(true);
      request.setRequestMethod("GET");
      request.setRequestProperty("User-Agent", "maplibre_flutter_gpu/0.0.1-dev");
      if (dataRange != null && !dataRange.isEmpty()) {
        request.setRequestProperty("Range", dataRange);
      }
      if (etag != null && !etag.isEmpty()) {
        request.setRequestProperty("If-None-Match", etag);
      }
      if (modified != null && !modified.isEmpty()) {
        request.setRequestProperty("If-Modified-Since", modified);
      }

      int responseCode = request.getResponseCode();
      byte[] body = readResponseBody(request, responseCode);
      respond(
          responseCode,
          request.getHeaderField("ETag"),
          request.getHeaderField("Last-Modified"),
          request.getHeaderField("Cache-Control"),
          request.getHeaderField("Expires"),
          request.getHeaderField("Retry-After"),
          request.getHeaderField("X-Rate-Limit-Reset"),
          body);
    } catch (SocketTimeoutException exception) {
      fail(TEMPORARY_ERROR, exception.toString());
    } catch (UnknownHostException exception) {
      fail(CONNECTION_ERROR, exception.toString());
    } catch (IOException exception) {
      fail(CONNECTION_ERROR, exception.toString());
    } finally {
      connection = null;
      if (request != null) {
        request.disconnect();
      }
    }
  }

  private static byte[] readResponseBody(HttpURLConnection request, int responseCode)
      throws IOException {
    if (responseCode == HttpURLConnection.HTTP_NOT_MODIFIED
        || responseCode == HttpURLConnection.HTTP_NO_CONTENT) {
      return new byte[0];
    }

    InputStream stream =
        responseCode >= HttpURLConnection.HTTP_BAD_REQUEST
            ? request.getErrorStream()
            : request.getInputStream();
    if (stream == null) {
      return new byte[0];
    }

    try (InputStream input = stream;
        ByteArrayOutputStream output = new ByteArrayOutputStream()) {
      byte[] buffer = new byte[16 * 1024];
      int count;
      while ((count = input.read(buffer)) != -1) {
        output.write(buffer, 0, count);
      }
      return output.toByteArray();
    }
  }

  private void respond(
      int code,
      String etag,
      String modified,
      String cacheControl,
      String expires,
      String retryAfter,
      String rateLimitReset,
      byte[] body) {
    synchronized (this) {
      if (!cancelled && nativePtr != 0) {
        nativeOnResponse(
            code,
            etag,
            modified,
            cacheControl,
            expires,
            retryAfter,
            rateLimitReset,
            body);
      }
    }
  }

  private void fail(int type, String message) {
    synchronized (this) {
      if (!cancelled && nativePtr != 0) {
        nativeOnFailure(type, message);
      }
    }
  }

  private native void nativeOnFailure(int type, String message);

  private native void nativeOnResponse(
      int code,
      String etag,
      String modified,
      String cacheControl,
      String expires,
      String retryAfter,
      String rateLimitReset,
      byte[] body);
}
