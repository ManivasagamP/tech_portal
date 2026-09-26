import Flutter
import UIKit

/// fe_ar: the FieldOps native AR engine on iPhone and iPad
/// (docs/ar-bim-overlay.md §6.1, CONTRACT C8).
///
/// Registers the three names the Dart side uses:
///  - MethodChannel "fusioneco/ar"        commands (method name = ArEngine command)
///  - EventChannel  "fusioneco/ar/events" low-rate events ({type: ...} maps)
///  - platform view "fusioneco/ar/view"   the camera + model surface (UiKitView)
/// Argument maps: packages/fe_ar/CHANNEL.md.
public class FeArPlugin: NSObject, FlutterPlugin {
    public static let methodChannel = "fusioneco/ar"
    public static let eventChannel = "fusioneco/ar/events"
    public static let viewType = "fusioneco/ar/view"

    private let controller: FeArController

    init(controller: FeArController) {
        self.controller = controller
        super.init()
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let controller = FeArController()
        let instance = FeArPlugin(controller: controller)
        let methods = FlutterMethodChannel(name: methodChannel, binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(instance, channel: methods)
        let events = FlutterEventChannel(name: eventChannel, binaryMessenger: registrar.messenger())
        events.setStreamHandler(controller)
        registrar.register(FeArViewFactory(controller: controller), withId: viewType)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        controller.handle(call, result: result)
    }
}
