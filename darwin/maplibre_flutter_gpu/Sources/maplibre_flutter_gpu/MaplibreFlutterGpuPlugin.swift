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
  private static let trackpadTiltChannelName =
    "dev.maplibre.flutter_gpu/macos_trackpad_tilt"

  private weak var flutterView: NSView?
  private var trackpadTiltChannel: FlutterMethodChannel?
  private var tiltRegions: [Int: NSRect] = [:]
  private var activeTiltRegion: Int?
  private var previousTrackpadDragPoint: NSPoint?
  private var eventMonitor: Any?
#endif

  public static func register(with registrar: FlutterPluginRegistrar) {
    _ = maplibre_flutter_gpu_force_link()
#if os(macOS)
    let plugin = MaplibreFlutterGpuPlugin()
    let channel = FlutterMethodChannel(
      name: trackpadTiltChannelName,
      binaryMessenger: registrar.messenger
    )
    plugin.flutterView = registrar.view
    plugin.trackpadTiltChannel = channel
    registrar.addMethodCallDelegate(plugin, channel: channel)
    plugin.installTrackpadMonitor()

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

#if os(macOS)
  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let arguments = call.arguments as? [String: Any],
          let id = arguments["id"] as? Int else {
      result(FlutterError(code: "invalid_arguments", message: nil, details: nil))
      return
    }
    switch call.method {
    case "setTiltRegion":
      guard let x = arguments["x"] as? Double,
            let y = arguments["y"] as? Double,
            let width = arguments["width"] as? Double,
            let height = arguments["height"] as? Double,
            let enabled = arguments["enabled"] as? Bool else {
        result(FlutterError(code: "invalid_arguments", message: nil, details: nil))
        return
      }
      if enabled {
        tiltRegions[id] = NSRect(x: x, y: y, width: width, height: height)
      } else {
        tiltRegions.removeValue(forKey: id)
      }
      result(nil)
    case "removeTiltRegion":
      tiltRegions.removeValue(forKey: id)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func installTrackpadMonitor() {
    let mouseDragEvents: NSEvent.EventTypeMask = [
      .leftMouseDown,
      .leftMouseDragged,
      .leftMouseUp,
    ]
    eventMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseDragEvents) {
      [weak self] event in
      self?.handleTrackpadDragEvent(event) ?? event
    }
  }

  private func startTrackpadTilt(at location: NSPoint) -> Bool {
    guard let region = tiltRegions.first(where: { $0.value.contains(location) })?.key else {
      return false
    }
    activeTiltRegion = region
    previousTrackpadDragPoint = location
    sendTrackpadTilt(id: region, phase: "start")
    return true
  }

  private func updateTrackpadTilt(deltaY: CGFloat) {
    guard let region = activeTiltRegion else { return }
    sendTrackpadTilt(id: region, phase: "update", deltaY: deltaY)
  }

  private func endTrackpadTilt() {
    guard let region = activeTiltRegion else { return }
    sendTrackpadTilt(id: region, phase: "end")
    activeTiltRegion = nil
    previousTrackpadDragPoint = nil
  }

  private func handleTrackpadDragEvent(_ event: NSEvent) -> NSEvent? {
    guard event.subtype == .touch, let flutterView else { return event }
    let point = flutterView.convert(event.locationInWindow, from: nil)
    switch event.type {
    case .leftMouseDown:
      return startTrackpadTilt(at: point) ? nil : event
    case .leftMouseDragged:
      guard activeTiltRegion != nil else { return event }
      if let previousTrackpadDragPoint {
        updateTrackpadTilt(deltaY: point.y - previousTrackpadDragPoint.y)
      }
      previousTrackpadDragPoint = point
      return nil
    case .leftMouseUp:
      guard activeTiltRegion != nil else { return event }
      endTrackpadTilt()
      return nil
    default:
      return event
    }
  }

  private func sendTrackpadTilt(id: Int, phase: String, deltaY: Double? = nil) {
    var arguments: [String: Any] = ["id": id, "phase": phase]
    if let deltaY {
      arguments["deltaY"] = deltaY
    }
    trackpadTiltChannel?.invokeMethod("trackpadTilt", arguments: arguments)
  }

  deinit {
    if let eventMonitor {
      NSEvent.removeMonitor(eventMonitor)
    }
  }
#endif
}
