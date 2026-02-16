import SwiftUI
import MetalKit

// MARK: - SwiftUI Wrapper

/// SwiftUI wrapper around InputMTKView for hosting the Metal renderer with input support.
struct MetalView: NSViewRepresentable {

    var fpsCounter: FPSCounter

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

        let renderer = Renderer(device: device, view: mtkView, fpsCounter: fpsCounter)
        context.coordinator.renderer = renderer
        mtkView.delegate = renderer
        mtkView.renderer = renderer

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
    private var keyMonitor: Any?
    
    /// Saved gravity state before right-click, so we can restore it on release.
    /// This ensures right-click acts as a temporary "boost" without interfering with 'G' key toggle.
    private var gravityStateBeforeRightClick: Bool = false

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // When launched via `swift run` from an embedded terminal (Cursor/VSCode),
        // the process isn't registered as a GUI app. This makes macOS treat it as
        // a regular app so it can receive keyboard events when focused.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeFirstResponder(self)
        installKeyMonitor()
    }

    /// SwiftUI's NSHostingView intercepts keyDown before it reaches embedded NSViews.
    /// A local event monitor catches key events at the NSApplication level, bypassing that.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else {
                print("[MONITOR] self is nil, passing event through")
                return event
            }
            guard event.window === self.window else { return event }
            print("[MONITOR] captured keyDown code=\(event.keyCode)")
            self.isPaused = false
            self.renderer?.handleKeyDown(with: event)
            return nil   // consume the event (prevents system beep)
        }
    }

    deinit {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    override func mouseDown(with event: NSEvent) {
        isPaused = false
        window?.makeFirstResponder(self)
        renderer?.camera.mouseDown(with: event, in: self)
    }

    override func mouseUp(with event: NSEvent) {
        renderer?.camera.mouseUp(with: event, in: self)
    }

    override func mouseDragged(with event: NSEvent) {
        isPaused = false
        renderer?.camera.mouseDragged(with: event, in: self)
    }

    override func rightMouseDown(with event: NSEvent) {
        isPaused = false
        // Save current state and enable gravity as a temporary boost
        gravityStateBeforeRightClick = renderer?.gravitySim.isEnabled ?? false
        renderer?.gravitySim.isEnabled = true
    }

    override func rightMouseUp(with event: NSEvent) {
        // Restore the saved state (respects 'G' key toggle)
        renderer?.gravitySim.isEnabled = gravityStateBeforeRightClick
    }

    override func scrollWheel(with event: NSEvent) {
        isPaused = false
        renderer?.camera.scrollWheel(with: event)
    }

    override func keyDown(with event: NSEvent) {
        isPaused = false
        renderer?.handleKeyDown(with: event)
    }
}
