import ARKit
import CoreImage
import Flutter
import MetalKit
import UIKit

/// Platform view type `fusioneco/ar/view` (CONTRACT C8).
final class FeArViewFactory: NSObject, FlutterPlatformViewFactory {
    private weak var controller: FeArController?

    init(controller: FeArController) {
        self.controller = controller
        super.init()
    }

    func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
        FeArPlatformView(frame: frame, controller: controller)
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        FlutterStandardMessageCodec.sharedInstance()
    }
}

/// The AR surface for UiKitView. Headless by design (docs/ar-bim-overlay.md
/// §6.2): it shows the camera and the model; every control is Flutter's.
final class FeArPlatformView: NSObject, FlutterPlatformView {
    let container: FeArContainerView
    private weak var controller: FeArController?

    init(frame: CGRect, controller: FeArController?) {
        container = FeArContainerView(frame: frame)
        self.controller = controller
        super.init()
        controller?.attach(self)
    }

    func view() -> UIView { container }

    deinit {
        let c = controller
        let me = ObjectIdentifier(self)
        DispatchQueue.main.async { c?.detach(me) }
    }
}

/// Filament draws into `modelView`'s CAMetalLayer. When the camera-feed
/// material isn't bundled, that layer is transparent and `cameraView` (Core
/// Image into an MTKView) draws the camera image underneath: slower, but the
/// app never shows a black AR screen because of a missing build step.
final class FeArContainerView: UIView {
    let modelView = FeArMetalView(frame: .zero)
    private var cameraView: MTKView?
    private var ciContext: CIContext?
    private var commandQueue: MTLCommandQueue?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        isUserInteractionEnabled = false // taps are Flutter's (pick / detectCornerAt)
        modelView.frame = bounds
        modelView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(modelView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    var interfaceOrientation: UIInterfaceOrientation {
        window?.windowScene?.interfaceOrientation ?? .portrait
    }

    /// Drawable size of the model layer, in pixels.
    var drawableSize: CGSize { modelView.metalLayer.drawableSize }

    func enableCameraFallback() {
        guard cameraView == nil, let device = MTLCreateSystemDefaultDevice() else { return }
        let v = MTKView(frame: bounds, device: device)
        v.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        v.framebufferOnly = false
        v.isPaused = true
        v.enableSetNeedsDisplay = false
        v.colorPixelFormat = .bgra8Unorm
        v.contentScaleFactor = UIScreen.main.nativeScale
        insertSubview(v, belowSubview: modelView)
        cameraView = v
        commandQueue = device.makeCommandQueue()
        ciContext = CIContext(mtlDevice: device)
    }

    /// The camera image as it appears on screen, in drawable pixels (Core
    /// Image's origin is bottom-left; ARKit's normalised image space is
    /// top-left).
    func cameraImage(_ frame: ARFrame, pixels: CGSize) -> CIImage {
        let pb = frame.capturedImage
        let w = CGFloat(CVPixelBufferGetWidth(pb)), h = CGFloat(CVPixelBufferGetHeight(pb))
        let toNormalisedImage = CGAffineTransform(scaleX: 1 / w, y: -1 / h).concatenating(CGAffineTransform(translationX: 0, y: 1))
        let display = frame.displayTransform(for: interfaceOrientation, viewportSize: bounds.size)
        let toPixels = CGAffineTransform(scaleX: 1, y: -1)
            .concatenating(CGAffineTransform(translationX: 0, y: 1))
            .concatenating(CGAffineTransform(scaleX: pixels.width, y: pixels.height))
        return CIImage(cvPixelBuffer: pb)
            .transformed(by: toNormalisedImage.concatenating(display).concatenating(toPixels))
            .cropped(to: CGRect(origin: .zero, size: pixels))
    }

    func drawCamera(_ frame: ARFrame) {
        guard let v = cameraView, let queue = commandQueue, let ctx = ciContext else { return }
        let px = v.drawableSize
        guard px.width > 0, px.height > 0, let drawable = v.currentDrawable, let cb = queue.makeCommandBuffer() else { return }
        ctx.render(cameraImage(frame, pixels: px), to: drawable.texture, commandBuffer: cb,
                   bounds: CGRect(origin: .zero, size: px), colorSpace: CGColorSpaceCreateDeviceRGB())
        cb.present(drawable)
        cb.commit()
    }

    /// Composites a model render over the camera image (capture() in fallback mode).
    func composite(model: UIImage, over frame: ARFrame) -> UIImage? {
        guard let cg = model.cgImage else { return model }
        let ctx = ciContext ?? CIContext()
        let px = CGSize(width: cg.width, height: cg.height)
        let camera = cameraImage(frame, pixels: px)
        let overlay = CIImage(cgImage: cg)
        let out = overlay.composited(over: camera)
        guard let result = ctx.createCGImage(out, from: CGRect(origin: .zero, size: px)) else { return model }
        return UIImage(cgImage: result)
    }
}

final class FeArMetalView: UIView {
    override class var layerClass: AnyClass { CAMetalLayer.self }

    var metalLayer: CAMetalLayer {
        // layerClass guarantees the type
        // swiftlint:disable:next force_cast
        layer as! CAMetalLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentScaleFactor = UIScreen.main.nativeScale
        isUserInteractionEnabled = false
        metalLayer.pixelFormat = .bgra8Unorm
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let s = contentScaleFactor
        metalLayer.drawableSize = CGSize(width: bounds.width * s, height: bounds.height * s)
    }
}
