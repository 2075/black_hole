import Foundation
import simd
import AppKit

/// Orbit camera centered on the black hole at the origin.
/// Ported from the C++ Camera struct in black_hole.cpp.
final class Camera {

    // MARK: - Orbit Parameters

    /// Look-at target (always the black hole center)
    var target: SIMD3<Float> = .zero

    /// Orbit distance from target (meters)
    var radius: Float = 6.34194e10

    /// Minimum / maximum orbit radius
    var minRadius: Float = 1e10
    var maxRadius: Float = 1e12

    /// Horizontal angle (radians)
    var azimuth: Float = 0.0

    /// Vertical angle (radians, 0 = north pole, pi = south pole)
    var elevation: Float = .pi / 2.0

    // MARK: - Sensitivity

    var orbitSpeed: Float = 0.01
    var zoomSpeed: Double = 25e9

    // MARK: - Interaction State

    private(set) var isDragging: Bool = false
    private(set) var isMoving: Bool = false
    private var lastMouseLocation: CGPoint = .zero

    // MARK: - Derived Properties

    /// Camera world-space position computed from spherical coordinates.
    var position: SIMD3<Float> {
        let e = simd_clamp(elevation, 0.01, .pi - 0.01)
        return SIMD3<Float>(
            radius * sin(e) * cos(azimuth),
            radius * cos(e),
            radius * sin(e) * sin(azimuth)
        )
    }

    /// Forward direction (toward the target).
    var forward: SIMD3<Float> {
        normalize(target - position)
    }

    /// Right direction (perpendicular to forward and world-up).
    var right: SIMD3<Float> {
        normalize(cross(forward, SIMD3<Float>(0, 1, 0)))
    }

    /// Recomputed up (orthogonal to forward and right).
    var up: SIMD3<Float> {
        cross(right, forward)
    }

    /// Half-angle tangent of the vertical field of view (60 deg).
    var tanHalfFov: Float {
        tan(Float.pi / 6.0) // tan(30°)
    }

    // MARK: - Uniform Upload

    /// Build the camera uniform struct ready for GPU upload.
    func uniforms(aspect: Float) -> CameraUniforms {
        CameraUniforms(
            position: position,
            _pad0: 0,
            right: right,
            _pad1: 0,
            up: up,
            _pad2: 0,
            forward: forward,
            _pad3: 0,
            tanHalfFov: tanHalfFov,
            aspect: aspect,
            moving: isDragging ? 1 : 0,
            _pad4: 0
        )
    }

    // MARK: - Input Handlers (AppKit)

    func mouseDown(with event: NSEvent, in view: NSView) {
        isDragging = true
        isMoving = true
        lastMouseLocation = event.locationInWindow
    }

    func mouseUp(with event: NSEvent, in view: NSView) {
        isDragging = false
        isMoving = false
    }

    func mouseDragged(with event: NSEvent, in view: NSView) {
        let location = event.locationInWindow
        let dx = Float(location.x - lastMouseLocation.x)
        let dy = Float(location.y - lastMouseLocation.y)

        azimuth += dx * orbitSpeed
        elevation -= dy * orbitSpeed
        elevation = simd_clamp(elevation, 0.01, .pi - 0.01)

        lastMouseLocation = location
        isMoving = true
    }

    func scrollWheel(with event: NSEvent) {
        radius -= Float(event.scrollingDeltaY * zoomSpeed)
        radius = simd_clamp(radius, minRadius, maxRadius)
        isMoving = true
    }
}
