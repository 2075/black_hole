import Foundation
import simd

// MARK: - Physical Constants

/// Speed of light in vacuum (m/s)
let kSpeedOfLight: Double = 299_792_458.0

/// Gravitational constant (m^3 kg^-1 s^-2)
let kGravitationalConstant: Double = 6.67430e-11

// MARK: - Sagittarius A* Parameters

/// Mass of Sagittarius A* (kg)
let kSagAMass: Double = 8.54e36

/// Schwarzschild radius of Sagittarius A*: r_s = 2GM/c^2 (m)
let kSagASchwarzschildRadius: Double = 2.0 * kGravitationalConstant * kSagAMass / (kSpeedOfLight * kSpeedOfLight)

// MARK: - Geodesic Integration Parameters

/// Affine parameter step size for RK4 integration
let kDLambda: Float = 1e7

/// Escape radius -- ray terminates when r exceeds this
let kEscapeRadius: Double = 1e30

/// Number of RK4 integration steps per ray
let kDefaultStepCount: Int = 60_000

// MARK: - Accretion Disk Parameters

/// Inner disk radius factor (multiplied by r_s)
let kDiskInnerFactor: Float = 2.2

/// Outer disk radius factor (multiplied by r_s)
let kDiskOuterFactor: Float = 5.2

/// Disk thickness (m)
let kDiskThickness: Float = 1e9

// MARK: - Compute Shader Workgroup

/// Workgroup size matching the Metal compute kernel threadgroup
let kWorkgroupSize: Int = 16

// MARK: - GPU Uniform Structs
// These must match the Metal shader buffer layouts exactly.

/// Camera uniform data uploaded to the compute shader (binding 1).
/// Layout must match `CameraUniforms` in geodesic.metal.
struct CameraUniforms {
    var position: SIMD3<Float>
    var _pad0: Float = 0
    var right: SIMD3<Float>
    var _pad1: Float = 0
    var up: SIMD3<Float>
    var _pad2: Float = 0
    var forward: SIMD3<Float>
    var _pad3: Float = 0
    var tanHalfFov: Float
    var aspect: Float
    var moving: Int32
    var stepCount: Int32
}

/// Accretion disk parameters (binding 2).
struct DiskUniforms {
    var innerRadius: Float
    var outerRadius: Float
    var diskNum: Float
    var thickness: Float
    var diskColor: SIMD4<Float>
}

/// Per-object data for sphere intersection in the compute shader (binding 3).
struct ObjectGPU {
    var posRadius: SIMD4<Float>  // xyz = position, w = radius
    var color: SIMD4<Float>      // rgba
    var mass: Float
    var _pad0: Float = 0
    var _pad1: Float = 0
    var _pad2: Float = 0
}

/// Objects uniform buffer header + array (binding 3).
struct ObjectsUniforms {
    var numObjects: Int32 = 0
    var _pad0: Float = 0
    var _pad1: Float = 0
    var _pad2: Float = 0
    var posRadius: (
        SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>,
        SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>,
        SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>,
        SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>
    ) = (.zero, .zero, .zero, .zero, .zero, .zero, .zero, .zero,
         .zero, .zero, .zero, .zero, .zero, .zero, .zero, .zero)
    var color: (
        SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>,
        SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>,
        SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>,
        SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>
    ) = (.zero, .zero, .zero, .zero, .zero, .zero, .zero, .zero,
         .zero, .zero, .zero, .zero, .zero, .zero, .zero, .zero)
    var mass: (
        Float, Float, Float, Float, Float, Float, Float, Float,
        Float, Float, Float, Float, Float, Float, Float, Float
    ) = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
}
