import CoreLocation
import Flutter
import MapLibre
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "UserLocationReference")!
    registrar.register(ReferenceFactory(messenger: registrar.messenger()), withId: "user-location-reference")
  }
}

final class ReferenceFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    return FlutterStandardMessageCodec.sharedInstance()
  }

  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    return ReferenceView(frame: frame, id: viewId, arguments: args as! [String: Any], messenger: messenger)
  }
}

final class FixedHeading: CLHeading {
  private let value: Double
  init(_ value: Double) {
    self.value = value
    super.init()
  }
  required init?(coder: NSCoder) { fatalError("Decoding is unsupported") }
  override var trueHeading: CLLocationDirection { value }
  override var magneticHeading: CLLocationDirection { value }
  override var headingAccuracy: CLLocationDirection { 1 }
  override var timestamp: Date { Date() }
}

/// Supplies fixed data without creating a Core Location manager or requesting permission.
final class FixedLocationManager: NSObject, MLNLocationManager {
  weak var delegate: MLNLocationManagerDelegate?
  var headingOrientation: CLDeviceOrientation = .portrait
  var authorizationStatus: CLAuthorizationStatus { .authorizedWhenInUse }
  var accuracyAuthorization: CLAccuracyAuthorization { .fullAccuracy }
  func requestAlwaysAuthorization() {}
  func requestWhenInUseAuthorization() {}
  func startUpdatingLocation() {}
  func stopUpdatingLocation() {}
  func startUpdatingHeading() {}
  func stopUpdatingHeading() {}
  func dismissHeadingCalibrationDisplay() {}
}

final class ReferenceView: NSObject, FlutterPlatformView, MLNMapViewDelegate {
  private let map: MLNMapView
  private let manager = FixedLocationManager()
  private let channel: FlutterMethodChannel
  private var styleLoaded = false
  private var scene: [String: Any] = [:]

  init(frame: CGRect, id: Int64, arguments: [String: Any], messenger: FlutterBinaryMessenger) {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("user-location-style.json")
    try! (arguments["style"] as! String).write(to: url, atomically: true, encoding: .utf8)
    map = MLNMapView(frame: frame, styleURL: url)
    channel = FlutterMethodChannel(name: "user-location-reference/\(id)", binaryMessenger: messenger)
    super.init()
    map.delegate = self
    map.locationManager = manager
    map.showsUserLocation = true
    map.showsUserHeadingIndicator = true
    map.compassView.isHidden = true
    map.logoView.isHidden = true
    map.attributionButton.isHidden = true
    map.isZoomEnabled = false
    map.isScrollEnabled = false
    map.isRotateEnabled = false
    map.isPitchEnabled = false
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { result(nil); return }
      switch call.method {
      case "configure":
        self.scene = call.arguments as! [String: Any]
        self.applyScene()
        result(nil)
      case "inspect":
        result(self.inspect())
      case "freeze":
        if let location = self.map.userLocation,
           let annotation = self.map.view(for: location) {
          self.freeze(annotation.layer)
        }
        result(self.inspect())
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  func view() -> UIView { map }

  func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
    styleLoaded = true
    applyScene()
  }

  private func applyScene() {
    guard !scene.isEmpty else { return }
    let coordinate = CLLocationCoordinate2D(latitude: number("latitude"), longitude: number("longitude"))
    map.setCenter(coordinate, zoomLevel: number("zoom"), direction: number("bearing"), animated: false)
    let camera = map.camera
    camera.pitch = number("pitch")
    map.setCamera(camera, animated: false)
    map.zoomLevel = number("zoom")
    let visible = scene["visible"] as? Bool ?? true
    map.showsUserLocation = visible
    map.showsUserHeadingIndicator = scene["heading"] != nil
    if visible {
      // The SDK ignores accuracy-only updates at an identical coordinate.
      // A one-centimeter intermediate fix makes the final requested fix observable.
      let intermediate = CLLocation(
        coordinate: CLLocationCoordinate2D(latitude: number("locationLatitude") + 0.0000001, longitude: number("locationLongitude")),
        altitude: 0,
        horizontalAccuracy: number("accuracy"),
        verticalAccuracy: -1,
        timestamp: Date()
      )
      manager.delegate?.locationManager(manager, didUpdate: [intermediate])
      let location = CLLocation(
        coordinate: CLLocationCoordinate2D(latitude: number("locationLatitude"), longitude: number("locationLongitude")),
        altitude: 0,
        horizontalAccuracy: number("accuracy"),
        verticalAccuracy: -1,
        timestamp: Date()
      )
      manager.delegate?.locationManager(manager, didUpdate: [location])
      if let heading = scene["heading"] as? NSNumber {
        manager.delegate?.locationManager(manager, didUpdate: FixedHeading(heading.doubleValue))
      }
    }
    map.setNeedsLayout()
    map.layoutIfNeeded()
  }

  private func number(_ key: String) -> Double { (scene[key] as! NSNumber).doubleValue }

  private func freeze(_ layer: CALayer) {
    layer.removeAllAnimations()
    layer.sublayers?.forEach(freeze)
  }

  private func inspect() -> [String: Any] {
    guard !scene.isEmpty else { return ["ready": false] }
    let coordinate = CLLocationCoordinate2D(latitude: number("locationLatitude"), longitude: number("locationLongitude"))
    let point = map.convert(coordinate, toPointTo: map)
    let visible = scene["visible"] as? Bool ?? true
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0
    map.tintColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
    let locationReady = !visible || (
      map.userLocation?.location?.horizontalAccuracy == number("accuracy") && map.isUserLocationVisible
    )
    return [
      "ready": styleLoaded && locationReady,
      "position": [point.x, point.y],
      "viewport": [map.bounds.width, map.bounds.height],
      "zoom": map.zoomLevel,
      "bearing": map.direction,
      "pitch": map.camera.pitch,
      "tint": [red, green, blue, alpha],
      "accuracy": map.userLocation?.location?.horizontalAccuracy ?? -1,
      "visible": map.isUserLocationVisible,
      "metersPerPoint": map.metersPerPoint(atLatitude: coordinate.latitude),
    ]
  }
}
