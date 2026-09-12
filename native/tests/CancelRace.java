import java.io.*;
import java.lang.reflect.*;
import java.net.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;

public class CancelRace {
  static final CountDownLatch enteredOpen = new CountDownLatch(1);
  static final CountDownLatch allowOpen = new CountDownLatch(1);
  static final CountDownLatch finished = new CountDownLatch(1);
  static final AtomicInteger responses = new AtomicInteger();
  static final AtomicInteger reads = new AtomicInteger();
  static final AtomicInteger disconnects = new AtomicInteger();
  public static void main(String[] args) throws Exception {
    URL.setURLStreamHandlerFactory(protocol -> protocol.equals("http") ? new URLStreamHandler() {
      protected URLConnection openConnection(URL url) throws IOException {
        enteredOpen.countDown();
        try { if (!allowOpen.await(5, TimeUnit.SECONDS)) throw new IOException("timeout"); }
        catch (InterruptedException e) { throw new IOException(e); }
        return new HttpURLConnection(url) {
          public void connect() {}
          public boolean usingProxy() { return false; }
          public int getResponseCode() { responses.incrementAndGet(); return 200; }
          public InputStream getInputStream() { reads.incrementAndGet(); return new ByteArrayInputStream(new byte[1024]); }
          public void disconnect() { disconnects.incrementAndGet(); finished.countDown(); }
        };
      }
    } : null);
    Class<?> type = Class.forName("org.maplibre.android.http.NativeHttpRequest");
    Constructor<?> ctor = type.getDeclaredConstructor(long.class, String.class, String.class, String.class, String.class, boolean.class);
    ctor.setAccessible(true);
    Object request = ctor.newInstance(1L, "http://audit.invalid/tile", "", "", "", false);
    if (!enteredOpen.await(5, TimeUnit.SECONDS)) throw new AssertionError("worker missing");
    type.getMethod("cancel").invoke(request);
    allowOpen.countDown();
    if (!finished.await(5, TimeUnit.SECONDS)) throw new AssertionError("worker stuck");
    System.out.println("After cancel completed: getResponseCode=" + responses + ", getInputStream=" + reads + ", disconnect=" + disconnects);
    if (responses.get() != 0 || reads.get() != 0) throw new AssertionError("cancelled request performed network I/O");
  }
}
