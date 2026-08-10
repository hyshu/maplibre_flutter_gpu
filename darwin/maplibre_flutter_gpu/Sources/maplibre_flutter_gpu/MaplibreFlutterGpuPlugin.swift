#if os(iOS)
import Flutter
#elseif os(macOS)
import AppKit
import FlutterMacOS
#endif
import MapLibreBridge

public final class MaplibreFlutterGpuPlugin: NSObject, FlutterPlugin {
#if os(macOS)
  private static var terminationObserver: NSObjectProtocol?
#endif

  public static func register(with registrar: FlutterPluginRegistrar) {
    _ = maplibre_flutter_gpu_force_link()
#if os(macOS)
    if terminationObserver == nil {
      terminationObserver = NotificationCenter.default.addObserver(
        forName: NSApplication.willTerminateNotification,
        object: nil,
        queue: nil
      ) { _ in
        maplibre_shutdown_all()
      }
    }
#endif
  }
}
