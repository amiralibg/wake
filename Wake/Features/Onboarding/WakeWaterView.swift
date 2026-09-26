import AppKit
import MetalKit
import SwiftUI

/// Draws `WakeWaterShader` full-bleed. SwiftUI hands it the bow's progress, the accent
/// and a drop counter; time and the pointer are tracked here, so the water moves at
/// display rate without re-running any SwiftUI body.
struct WakeWaterView: NSViewRepresentable {
    let accent: Color
    let progress: Double
    let dropID: Int
    let isStill: Bool

    func makeCoordinator() -> Renderer { Renderer() }

    func makeNSView(context: Context) -> WaterMTKView {
        let view = WaterMTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.renderer = context.coordinator
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.preferredFramesPerSecond = 60
        // The water is soft: one pixel per point is enough, and on Retina that's a
        // quarter of the fragments.
        view.autoResizeDrawable = false
        view.clearColor = MTLClearColor(red: 0.055, green: 0.051, blue: 0.047, alpha: 1)
        view.delegate = context.coordinator
        context.coordinator.prepare(device: view.device)
        return view
    }

    func updateNSView(_ view: WaterMTKView, context: Context) {
        let renderer = context.coordinator
        renderer.progress = progress
        renderer.accent = NSColor(accent).usingColorSpace(.sRGB).map {
            SIMD4(Float($0.redComponent), Float($0.greenComponent), Float($0.blueComponent), 1)
        } ?? SIMD4(0.2, 0.5, 1, 1)
        if renderer.dropID != dropID {
            if renderer.dropID != nil, !isStill { renderer.dropNow() }
            renderer.dropID = dropID
        }
        renderer.isStill = isStill
        view.isStill = isStill
    }

    /// Tracks the pointer itself: SwiftUI hover would re-render the view on every move.
    final class WaterMTKView: MTKView {
        weak var renderer: Renderer?
        private var tracking: NSTrackingArea?
        /// Rides the wake's bow; placed by the renderer every frame.
        let boat = PaperBoatLayer()
        private var occlusionObserver: NSObjectProtocol?

        /// Reduce Motion: draw on demand only.
        var isStill = false {
            didSet { if isStill != oldValue { updatePaused() } }
        }

        /// Runs only while someone can see it: still water draws on demand, and the
        /// display link stops while the window is hidden or fully covered.
        private func updatePaused() {
            let visible = window?.occlusionState.contains(.visible) ?? false
            isPaused = isStill || !visible
            enableSetNeedsDisplay = isStill
            if isStill || visible { needsDisplay = true }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let occlusionObserver { NotificationCenter.default.removeObserver(occlusionObserver) }
            occlusionObserver = window.map { window in
                NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.updatePaused() }
                }
            }
            updatePaused()
        }

        override init(frame: CGRect, device: MTLDevice?) {
            super.init(frame: frame, device: device)
            wantsLayer = true
            layer?.addSublayer(boat)
        }

        @available(*, unavailable)
        required init(coder: NSCoder) { fatalError() }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let tracking { removeTrackingArea(tracking) }
            let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self)
            addTrackingArea(area)
            tracking = area
        }

        override func mouseMoved(with event: NSEvent) {
            super.mouseMoved(with: event)
            let point = convert(event.locationInWindow, from: nil)
            renderer?.pointerMoved(to: CGPoint(x: point.x, y: isFlipped ? point.y : bounds.height - point.y))
        }

    }

    /// Layout must match `Uniforms` in the shader: SIMD alignment is the same on both sides.
    private struct Uniforms {
        var size: SIMD2<Float>
        var time: Float
        var dropAge: Float
        var bowPoint: SIMD2<Float>
        var dropPoint: SIMD2<Float>
        var pointerPoint: SIMD2<Float>
        var pointerStrength: Float
        var contentScale: Float
        var accent: SIMD4<Float>
    }

    @MainActor
    final class Renderer: NSObject, MTKViewDelegate {
        var progress: Double = 0
        var accent = SIMD4<Float>(0.2, 0.5, 1, 1)
        var dropID: Int?
        var isStill = false
        var contentScale: Float = 2

        private var queue: MTLCommandQueue?
        private var pipeline: MTLRenderPipelineState?
        private let start = CACurrentMediaTime()
        private var size = CGSize.zero
        private var drop: (point: SIMD2<Float>, time: Double)?
        private var pointer: (point: SIMD2<Float>, time: Double)?

        private var now: Double { isStill ? 0 : CACurrentMediaTime() - start }

        func prepare(device: MTLDevice?) {
            guard let device else { return }
            queue = device.makeCommandQueue()
            do {
                let library = try device.makeLibrary(source: WakeWaterShader.source, options: nil)
                let descriptor = MTLRenderPipelineDescriptor()
                descriptor.vertexFunction = library.makeFunction(name: "wakeVertex")
                descriptor.fragmentFunction = library.makeFunction(name: "wakeFragment")
                descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
                pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
            } catch {
                // The clear colour (plain ink) stands in; onboarding still works.
                assertionFailure("Wake water shader failed: \(error)")
            }
        }

        /// The point of light at the head of the wake, in points.
        private func bow(at t: Double) -> SIMD2<Float> {
            SIMD2(
                Float(size.width * (0.2 + 0.6 * progress) + 14 * sin(t * 0.4)),
                Float(size.height * 0.82 + 8 * cos(t * 0.33))
            )
        }

        func dropNow() {
            let t = now
            drop = (bow(at: t), t)
        }

        func pointerMoved(to point: CGPoint) {
            guard !isStill else { return }
            pointer = (SIMD2(Float(point.x), Float(point.y)), now)
        }

        nonisolated func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        nonisolated func draw(in view: MTKView) {
            MainActor.assumeIsolated { render(in: view) }
        }

        private func render(in view: MTKView) {
            size = view.bounds.size
            guard size.width > 0, size.height > 0 else { return }
            let pixels = CGSize(width: size.width.rounded(), height: size.height.rounded())
            if view.drawableSize != pixels { view.drawableSize = pixels }
            contentScale = Float(pixels.width / size.width)
            guard let pipeline, let queue, let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
                  let buffer = queue.makeCommandBuffer(), let encoder = buffer.makeRenderCommandEncoder(descriptor: pass)
            else { return }
            let t = now
            if let water = view as? WaterMTKView {
                // AppKit layers count y from the bottom; the shader, from the top.
                let bow = bow(at: t)
                water.boat.place(at: CGPoint(x: CGFloat(bow.x), y: size.height - CGFloat(bow.y)), time: t, still: isStill)
            }
            var uniforms = Uniforms(
                size: SIMD2(Float(size.width), Float(size.height)),
                time: Float(t),
                dropAge: drop.map { Float(t - $0.time) } ?? 100,
                bowPoint: bow(at: t),
                dropPoint: drop?.point ?? .zero,
                pointerPoint: pointer?.point ?? .zero,
                pointerStrength: pointer.map { Float(max(0, 1 - (t - $0.time) / 1.4)) } ?? 0,
                contentScale: contentScale,
                accent: accent
            )
            encoder.setRenderPipelineState(pipeline)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
            buffer.present(drawable)
            buffer.commit()
        }
    }
}

/// An origami paper boat (a page folded into a boat) in two-tone vector: the hull,
/// and the two folds of the sail, lit from the left. It sits where the wake starts,
/// bobbing with the swell.
final class PaperBoatLayer: CALayer {
    private static let size = CGSize(width: 54, height: 36)
    /// Where the waterline meets the middle of the hull, in the boat's own space.
    private static let waterline = CGPoint(x: 27, y: 7)

    override init() {
        super.init()
        bounds = CGRect(origin: .zero, size: Self.size)
        anchorPoint = CGPoint(x: Self.waterline.x / Self.size.width, y: Self.waterline.y / Self.size.height)
        shadowColor = NSColor.black.cgColor
        shadowOpacity = 0.35
        shadowRadius = 6
        shadowOffset = CGSize(width: 0, height: -3)
        let paper = { (white: CGFloat) in NSColor(calibratedRed: white, green: white * 0.99, blue: white * 0.95, alpha: 1).cgColor }
        // y runs up. Hull first, then the sail folds on top.
        addFold([(0, 16), (27, 16), (27, 2), (11, 2)], paper(0.74))   // hull, shaded side
        addFold([(27, 16), (54, 16), (43, 2), (27, 2)], paper(0.9))   // hull, lit side
        addFold([(15, 16), (27, 36), (27, 16)], paper(0.84))          // sail, back fold
        addFold([(27, 16), (27, 36), (39, 16)], paper(0.98))          // sail, front fold
        shadowPath = CGPath(rect: CGRect(x: 6, y: 0, width: 42, height: 10), transform: nil)
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func addFold(_ points: [(CGFloat, CGFloat)], _ color: CGColor) {
        let path = CGMutablePath()
        path.addLines(between: points.map { CGPoint(x: $0.0, y: $0.1) })
        path.closeSubpath()
        let fold = CAShapeLayer()
        fold.path = path
        fold.fillColor = color
        // A hairline where folds meet reads as a crease.
        fold.strokeColor = NSColor.black.withAlphaComponent(0.08).cgColor
        fold.lineWidth = 0.5
        fold.lineJoin = .round
        addSublayer(fold)
    }

    /// Moves the boat to the bow and rocks it gently, without implicit animations.
    func place(at point: CGPoint, time: Double, still: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let bob = still ? 0 : 1.6 * sin(time * 2.1)
        let rock = still ? 0 : 0.045 * sin(time * 1.7 + 0.6)
        position = CGPoint(x: point.x, y: point.y + bob)
        setAffineTransform(CGAffineTransform(rotationAngle: rock))
        CATransaction.commit()
    }
}
