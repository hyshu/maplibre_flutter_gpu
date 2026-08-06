#if os(iOS)
import Flutter
#elseif os(macOS)
import FlutterMacOS
#endif
import MapLibreBridge

public final class MaplibreFlutterGpuPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    _ = maplibre_flutter_gpu_force_link()
  }
}
