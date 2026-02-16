import Foundation
import simd

/// CPU-side N-body gravity simulation.
/// Ported from the gravity loop in black_hole.cpp main().
final class GravitySim {

    /// Whether gravity integration is active (toggled by 'G' key / right-click).
    var isEnabled: Bool = false

    /// Advance all objects by one frame using pairwise Newtonian gravity.
    ///
    /// This matches the brute-force O(n^2) loop in the original C++ code.
    /// For a small number of objects (< 16) this is perfectly adequate.
    ///
    /// - Parameters:
    ///   - objects: The scene objects to update in-place.
    ///   - dt: Frame delta time in seconds (currently unused in the C++ code,
    ///         which integrates in a unit-timestep style).
    func step(objects: inout [SceneObject], dt: Float) {
        guard isEnabled else { return }

        let G = Float(kGravitationalConstant)
        let count = objects.count

        for i in 0..<count {
            for j in 0..<count {
                if i == j { continue }

                let delta = objects[j].position - objects[i].position
                let distance = simd_length(delta)
                guard distance > 0 else { continue }

                let direction = delta / distance
                let force = (G * objects[i].mass * objects[j].mass) / (distance * distance)
                let acceleration = force / objects[i].mass

                objects[i].velocity += direction * acceleration
                objects[i].position += objects[i].velocity
            }
        }
    }
}
