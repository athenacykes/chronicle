import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  static var sharedFlutterViewController: FlutterViewController?

  private func logSettingsMenu(_ message: String) {
    NSLog("[Chronicle][SettingsMenu] %@", message)
  }

  override func awakeFromNib() {
    logSettingsMenu("MainFlutterWindow.awakeFromNib")
    let flutterViewController = FlutterViewController()
    MainFlutterWindow.sharedFlutterViewController = flutterViewController
    logSettingsMenu(
      "MainFlutterWindow stored shared FlutterViewController=\(ObjectIdentifier(flutterViewController).hashValue)"
    )
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
