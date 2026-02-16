import SwiftUI
import MetalKit

// MARK: - SwiftUI Wrapper

/// SwiftUI wrapper around MTKView for hosting the Metal renderer.
struct MetalView: NSViewRepresentable {

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> MTKView {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device")
        }

        let mtkView = MTKView(frame: .zero, device: device)
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.depthStencilPixelFormat = .depth32Float
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        mtkView.preferredFramesPerSecond = 60
        mtkView.enableSetNeedsDisplay = false // Continuous redraw
        mtkView.isPaused = false

        let renderer = Renderer(device: device, view: mtkView)
        context.coordinator.renderer = renderer
        mtkView.delegate = renderer

        return mtkView
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        // No dynamic SwiftUI state to push into the view yet
    }

    // MARK: - Coordinator

    /// Holds a strong reference to the renderer so it stays alive.
    class Coordinator {
        var renderer: Renderer?
    }
}

// MARK: - Input Handling

/// NSView subclass that forwards mouse/keyboard events to the renderer's camera.
/// TODO: Wire this up as a subclass of MTKView or as an overlay to capture input.
class InputMTKView: MTKView {

    var camera: Camera?

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        camera?.mouseDown(with: event, in: self)
    }

    override func mouseUp(with event: NSEvent) {
        camera?.mouseUp(with: event, in: self)
    }

    override func mouseDragged(with event: NSEvent) {
        camera?.mouseDragged(with: event, in: self)
    }

    override func rightMouseDown(with event: NSEvent) {
        camera?.rightMouseDown(with: event)
    }

    override func rightMouseUp(with event: NSEvent) {
        camera?.rightMouseUp(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        camera?.scrollWheel(with: event)
    }

    override func keyDown(with event: NSEvent) {
        camera?.keyDown(with: event)
    }
}
