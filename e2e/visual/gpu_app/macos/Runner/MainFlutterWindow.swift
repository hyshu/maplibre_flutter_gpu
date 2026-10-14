import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.setContentSize(NSSize(width: 800, height: 600))
    self.center()

    // Benchmarks need every frame rendered. A floating window that follows
    // every Space stays visible while other applications are in use, so
    // samples are not invalidated by occlusion.
    if ProcessInfo.processInfo.environment["VISUAL_E2E_FLOATING"] == "1" {
      self.level = .floating
      self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
      self.hidesOnDeactivate = false
      if let screen = self.screen ?? NSScreen.main {
        let visible = screen.visibleFrame
        self.setFrameOrigin(
          NSPoint(x: visible.maxX - self.frame.width, y: visible.minY))
      }
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
