import Cocoa
import FlutterMacOS

/// Flutter plugin for PSD Metal compositing on macOS.
public class DartPsdToolPlugin: NSObject, FlutterPlugin {
    private var compositor: PsdMetalCompositor?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "dart_psd_tool/metal",
            binaryMessenger: registrar.messenger
        )
        let instance = DartPsdToolPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "isAvailable":
            result(PsdMetalCompositor.isAvailable)

        case "initialize":
            do {
                compositor = try PsdMetalCompositor()
                result(true)
            } catch {
                result(FlutterError(
                    code: "METAL_INIT_FAILED",
                    message: error.localizedDescription,
                    details: nil
                ))
            }

        case "composite":
            guard let compositor = compositor else {
                result(FlutterError(
                    code: "NOT_INITIALIZED",
                    message: "Metal compositor not initialized. Call initialize() first.",
                    details: nil
                ))
                return
            }

            guard let args = call.arguments as? [String: Any],
                  let srcBytes = args["src"] as? FlutterStandardTypedData,
                  let dstBytes = args["dst"] as? FlutterStandardTypedData,
                  let width = args["width"] as? Int,
                  let height = args["height"] as? Int,
                  let blendMode = args["blendMode"] as? Int,
                  let opacity = args["opacity"] as? Double else {
                result(FlutterError(
                    code: "INVALID_ARGS",
                    message: "Missing or invalid arguments",
                    details: nil
                ))
                return
            }

            // Run compositing on a background queue to avoid blocking the platform thread
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let output = try compositor.composite(
                        srcBytes: srcBytes.data,
                        dstBytes: dstBytes.data,
                        width: width,
                        height: height,
                        blendMode: blendMode,
                        opacity: Float(opacity)
                    )
                    DispatchQueue.main.async {
                        result(FlutterStandardTypedData(bytes: output))
                    }
                } catch {
                    DispatchQueue.main.async {
                        result(FlutterError(
                            code: "COMPOSITE_FAILED",
                            message: error.localizedDescription,
                            details: nil
                        ))
                    }
                }
            }

        case "dispose":
            compositor = nil
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }
}
