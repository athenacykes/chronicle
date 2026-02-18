import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private var appChannel: FlutterMethodChannel?

  private func logSettingsMenu(_ message: String) {
    NSLog("[Chronicle][SettingsMenu] %@", message)
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
    logSettingsMenu("applicationDidFinishLaunching")
    _ = resolveAppChannel()
    configureSettingsMenuItem()
    DispatchQueue.main.async { [weak self] in
      self?.logSettingsMenu("reconfiguring menu item on next runloop")
      self?.configureSettingsMenuItem()
    }
  }

  override func applicationDidBecomeActive(_ notification: Notification) {
    super.applicationDidBecomeActive(notification)
    logSettingsMenu("applicationDidBecomeActive")
    configureSettingsMenuItem()
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  private func configureSettingsMenuItem() {
    guard let appMenu = NSApp.mainMenu?.item(at: 0)?.submenu else {
      logSettingsMenu("configureSettingsMenuItem: app menu not found")
      return
    }
    guard let settingsItem = appMenu.items.first(where: { $0.keyEquivalent == "," }) else {
      logSettingsMenu("configureSettingsMenuItem: settings item (Cmd+,) not found")
      return
    }

    settingsItem.title = "Settings…"
    settingsItem.target = self
    settingsItem.action = #selector(showPreferencesWindow(_:))
    settingsItem.isEnabled = true
    logSettingsMenu(
      "configureSettingsMenuItem: wired title='\(settingsItem.title)', enabled=\(settingsItem.isEnabled), action=\(String(describing: settingsItem.action))"
    )
  }

  @IBAction func openSettingsFromMenu(_ sender: Any?) {
    let senderType = sender.map { String(describing: type(of: $0)) } ?? "nil"
    logSettingsMenu("openSettingsFromMenu invoked (sender=\(senderType))")

    if let channel = resolveAppChannel() {
      logSettingsMenu("resolved channel, invoking openSettings")
      channel.invokeMethod("openSettings", arguments: nil) { [weak self] result in
        self?.logSettingsMenu("invokeMethod callback result=\(String(describing: result))")
      }
      return
    }

    logSettingsMenu("channel unavailable, retrying invoke on next runloop")
    DispatchQueue.main.async { [weak self] in
      guard let self else {
        return
      }
      if let retryChannel = self.resolveAppChannel() {
        self.logSettingsMenu("retry resolved channel, invoking openSettings")
        retryChannel.invokeMethod("openSettings", arguments: nil) { [weak self] result in
          self?.logSettingsMenu("retry invokeMethod callback result=\(String(describing: result))")
        }
      } else {
        self.logSettingsMenu("retry failed: no channel available")
      }
    }
  }

  @IBAction func showPreferencesWindow(_ sender: Any?) {
    logSettingsMenu("showPreferencesWindow invoked")
    openSettingsFromMenu(sender)
  }

  @objc func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
    if menuItem.action == #selector(openSettingsFromMenu(_:))
      || menuItem.action == #selector(showPreferencesWindow(_:))
    {
      return true
    }
    return true
  }

  private func resolveAppChannel() -> FlutterMethodChannel? {
    let flutterViewController: FlutterViewController?
    let source: String
    if let fromShared = MainFlutterWindow.sharedFlutterViewController {
      flutterViewController = fromShared
      source = "MainFlutterWindow.sharedFlutterViewController"
    } else if let fromMainFlutterWindow = mainFlutterWindow?.contentViewController as? FlutterViewController {
      flutterViewController = fromMainFlutterWindow
      source = "mainFlutterWindow"
    } else if let fromMainFlutterWindowChild = findFlutterViewController(
      in: mainFlutterWindow?.contentViewController
    ) {
      flutterViewController = fromMainFlutterWindowChild
      source = "mainFlutterWindow.childController"
    } else if let fromMainWindow = NSApp.mainWindow?.contentViewController as? FlutterViewController {
      flutterViewController = fromMainWindow
      source = "NSApp.mainWindow"
    } else if let fromMainWindowChild = findFlutterViewController(in: NSApp.mainWindow?.contentViewController) {
      flutterViewController = fromMainWindowChild
      source = "NSApp.mainWindow.childController"
    } else if let fromAnyWindow = NSApp.windows.compactMap({ $0.contentViewController as? FlutterViewController }).first {
      flutterViewController = fromAnyWindow
      source = "NSApp.windows.first"
    } else if let fromAnyWindowChild = NSApp.windows.compactMap({
      findFlutterViewController(in: $0.contentViewController)
    }).first {
      flutterViewController = fromAnyWindowChild
      source = "NSApp.windows.childController"
    } else {
      flutterViewController = nil
      source = "none"
    }

    guard let flutterViewController else {
      let windowControllerTypes = NSApp.windows
        .map { window in
          String(describing: type(of: window.contentViewController))
        }
        .joined(separator: ", ")
      logSettingsMenu(
        "resolveAppChannel: no FlutterViewController found (windows=\(NSApp.windows.count), source=\(source), controllerTypes=[\(windowControllerTypes)])"
      )
      return nil
    }

    let channel = FlutterMethodChannel(
      name: "chronicle/app",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    appChannel = channel
    logSettingsMenu(
      "resolveAppChannel: channel ready via \(source), viewController=\(ObjectIdentifier(flutterViewController).hashValue)"
    )
    return channel
  }

  private func findFlutterViewController(
    in controller: NSViewController?
  ) -> FlutterViewController? {
    guard let controller else {
      return nil
    }
    if let flutterViewController = controller as? FlutterViewController {
      return flutterViewController
    }
    for child in controller.children {
      if let flutterViewController = findFlutterViewController(in: child) {
        return flutterViewController
      }
    }
    if let presentedControllers = controller.presentedViewControllers {
      for presented in presentedControllers {
        if let flutterViewController = findFlutterViewController(in: presented) {
          return flutterViewController
        }
      }
    }
    return nil
  }
}
