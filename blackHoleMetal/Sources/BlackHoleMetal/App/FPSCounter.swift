import Foundation
import Observation
import QuartzCore

/// Tracks frame rate by counting draw calls over a rolling one-second window.
@Observable
final class FPSCounter {
    private(set) var fps: Double = 0

    private var frameCount: Int = 0
    private var lastSampleTime: CFTimeInterval = CACurrentMediaTime()

    /// Call once per frame from the render loop.
    func tick() {
        frameCount += 1
        let now = CACurrentMediaTime()
        let elapsed = now - lastSampleTime
        if elapsed >= 1.0 {
            fps = Double(frameCount) / elapsed
            frameCount = 0
            lastSampleTime = now
        }
    }
}
