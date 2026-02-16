import SwiftUI
import MetalKit

// MARK: - SwiftUI Wrapper

/// SwiftUI wrapper around InputMTKView for hosting the Metal renderer with input support.
struct MetalView: NSViewRepresentable {

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> InputMTKView {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device")
        }

        let mtkView = InputMTKView(frame: .zero, device: device)
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.depthStencilPixelFormat = .depth32Float
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        mtkView.preferredFramesPerSecond = 60
        mtkView.enableSetNeedsDisplay = false
        mtkView.isPaused = false

        let renderer = Renderer(device: device, view: mtkView)
        context.coordinator.renderer = renderer
        mtkView.delegate = renderer
        mtkView.renderer = renderer

        // Make the view the first responder so it receives keyboard events
        DispatchQueue.main.async {
            mtkView.window?.makeFirstResponder(mtkView)
        }

        return mtkView
    }

    func updateNSView(_ nsView: InputMTKView, context: Context) {
        // No dynamic SwiftUI state to push into the view yet
    }

    // MARK: - Coordinator

    /// Holds a strong reference to the renderer so it stays alive.
    class Coordinator {
        var renderer: Renderer?
    }
}

// MARK: - Input Handling

/// MTKView subclass that forwards mouse/keyboard events to the renderer's camera and gravity sim.
class InputMTKView: MTKView {

    weak var renderer: Renderer?

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        renderer?.camera.mouseDown(with: event, in: self)
    }

    override func mouseUp(with event: NSEvent) {
        renderer?.camera.mouseUp(with: event, in: self)
    }

    override func mouseDragged(with event: NSEvent) {
        renderer?.camera.mouseDragged(with: event, in: self)
    }

    override func rightMouseDown(with event: NSEvent) {
        renderer?.gravitySim.isEnabled = true
    }

    override func rightMouseUp(with event: NSEvent) {
        renderer?.gravitySim.isEnabled = false
    }

    override func scrollWheel(with event: NSEvent) {
        renderer?.camera.scrollWheel(with: event)
    }

    override func keyDown(with event: NSEvent) {
        renderer?.handleKeyDown(with: event)
    }
}
