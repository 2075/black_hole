import Foundation
import simd

/// Model of a Schwarzschild black hole.
/// Ported from the C++ BlackHole struct in black_hole.cpp.
struct BlackHole {
    /// World-space position
    var position: SIMD3<Float>

    /// Mass (kg)
    var mass: Double

    /// Schwarzschild radius: r_s = 2GM/c^2
    var schwarzschildRadius: Double {
        2.0 * kGravitationalConstant * mass / (kSpeedOfLight * kSpeedOfLight)
    }

    /// Check if a point lies within the event horizon.
    func intercepts(point: SIMD3<Float>) -> Bool {
        let delta = SIMD3<Double>(point) - SIMD3<Double>(position)
        let dist2 = simd_length_squared(delta)
        return dist2 < schwarzschildRadius * schwarzschildRadius
    }
}

/// Scene object with position, radius, color, mass, and velocity.
/// Ported from the C++ ObjectData struct.
struct SceneObject {
    /// xyz = position, w = radius
    var posRadius: SIMD4<Float>

    /// rgba color
    var color: SIMD4<Float>

    /// Mass (kg)
    var mass: Float

    /// Velocity for N-body simulation (m/s)
    var velocity: SIMD3<Float> = .zero

    /// Convenience position accessor
    var position: SIMD3<Float> {
        get { SIMD3<Float>(posRadius.x, posRadius.y, posRadius.z) }
        set {
            posRadius.x = newValue.x
            posRadius.y = newValue.y
            posRadius.z = newValue.z
        }
    }

    /// Convenience radius accessor
    var radius: Float {
        get { posRadius.w }
        set { posRadius.w = newValue }
    }
}

// MARK: - Default Scene

/// Sagittarius A* black hole at the origin.
let sagA = BlackHole(
    position: SIMD3<Float>(0, 0, 0),
    mass: kSagAMass
)

/// Default scene objects matching the C++ `objects` vector.
func makeDefaultSceneObjects() -> [SceneObject] {
    [
        SceneObject(
            posRadius: SIMD4<Float>(4e11, 0, 0, 4e10),
            color: SIMD4<Float>(1, 1, 0, 1),
            mass: 1.98892e30
        ),
        SceneObject(
            posRadius: SIMD4<Float>(0, 0, 4e11, 4e10),
            color: SIMD4<Float>(1, 0, 0, 1),
            mass: 1.98892e30
        ),
        SceneObject(
            posRadius: SIMD4<Float>(0, 0, 0, Float(sagA.schwarzschildRadius)),
            color: SIMD4<Float>(0, 0, 0, 1),
            mass: Float(sagA.mass)
        ),
    ]
}
