# Physics Reference — Black Hole Simulation

Extracted from the C++/GLSL codebase for use by both migration tracks (Swift+Metal and Rust+wgpu).

---

## 1. Physical Constants

| Symbol | Value | Unit | Description | Source |
|--------|-------|------|-------------|--------|
| `c` | `299792458.0` | m/s | Speed of light | all `.cpp` files |
| `G` | `6.67430e-11` | m³ kg⁻¹ s⁻² | Gravitational constant | all `.cpp` files |
| `M_SagA` | `8.54e36` | kg | Mass of Sagittarius A* | `BlackHole SagA(…, 8.54e36)` |
| `r_s` | `2GM/c² ≈ 1.269e10` | m | Schwarzschild radius of Sag A* | computed at init; hardcoded in `geodesic.comp` |
| `M_sun` | `1.98892e30` | kg | Solar mass (used for orbiting stars) | `black_hole.cpp` objects list |

### Derived / Precomputed

```
r_s = 2 * G * M / c²
```

For Sag A*: `r_s = 2 * 6.67430e-11 * 8.54e36 / (299792458)² ≈ 1.269e10 m`

The compute shader (`geodesic.comp`) hardcodes this as `const float SagA_rs = 1.269e10;` for GPU performance. The CPU code computes it at runtime in the `BlackHole` constructor.

---

## 2. Schwarzschild Metric

The simulation uses the **Schwarzschild metric** for a non-rotating, uncharged black hole. The key metric function is:

```
f(r) = 1 − r_s / r
```

Where:
- `r` is the radial coordinate (distance from black hole center)
- `r_s` is the Schwarzschild radius (event horizon)
- `f(r) → 0` at the event horizon (`r = r_s`)
- `f(r) → 1` at infinity (flat spacetime)

---

## 3. Coordinate Systems

### 3.1 Cartesian ↔ Spherical Conversion

**Cartesian → Spherical:**
```
r     = sqrt(x² + y² + z²)
θ     = acos(z / r)
φ     = atan2(y, x)
```

**Spherical → Cartesian:**
```
x = r sin(θ) cos(φ)
y = r sin(θ) sin(φ)
z = r cos(θ)
```

### 3.2 Direction Vector Conversion (Cartesian → Spherical Basis)

Given a Cartesian direction `(dx, dy, dz)`:

```
dr/dλ     =  sin(θ)cos(φ) · dx + sin(θ)sin(φ) · dy + cos(θ) · dz
dθ/dλ     = [cos(θ)cos(φ) · dx + cos(θ)sin(φ) · dy − sin(θ) · dz] / r
dφ/dλ     = [−sin(φ) · dx + cos(φ) · dy] / (r sin(θ))
```

**Source:** `initRay()` in `geodesic.comp`, `Ray` constructor in `CPU-geodesic.cpp`

### 3.3 2D Polar (for 2D lensing demo)

**Cartesian → Polar:**
```
r   = sqrt(x² + y²)
φ   = atan2(y, x)
```

**Direction conversion:**
```
dr/dλ   =  cos(φ) · dx + sin(φ) · dy
dφ/dλ   = (−sin(φ) · dx + cos(φ) · dy) / r
```

**Polar → Cartesian:**
```
x = r cos(φ)
y = r sin(φ)
```

---

## 4. Conserved Quantities (Null Geodesics)

For null geodesics (light rays) in Schwarzschild spacetime, two quantities are conserved along the trajectory:

### 3D Case

**Angular momentum:**
```
L = r² sin(θ) · dφ/dλ
```

**Energy parameter (related to coordinate time derivative):**
```
dt/dλ = sqrt( (dr/dλ)² / f + r² · ((dθ/dλ)² + sin²(θ) · (dφ/dλ)²) )
E     = f · dt/dλ
```

**Source:** `initRay()` in `geodesic.comp`, `Ray` constructor in `CPU-geodesic.cpp`

### 2D Case

```
L     = r² · dφ/dλ
dt/dλ = sqrt( (dr/dλ)² / f² + r² · (dφ/dλ)² / f )
E     = f · dt/dλ
```

**Source:** `Ray` constructor in `2D_lensing.cpp`

> **Note:** The 2D formula uses `f²` in the denominator of the `dr` term (equatorial restriction), while the 3D formula uses `f`. This reflects the reduced metric in the equatorial plane.

---

## 5. Geodesic Equations of Motion

These are the second-order ODEs governing photon trajectories in Schwarzschild spacetime, written as a first-order system.

### 5.1 3D Schwarzschild Null Geodesic

State vector: `y = (r, θ, φ, dr/dλ, dθ/dλ, dφ/dλ)`

**First derivatives (trivial):**
```
d(r)/dλ  = dr/dλ
d(θ)/dλ  = dθ/dλ
d(φ)/dλ  = dφ/dλ
```

**Second derivatives (the geodesic equation):**
```
f = 1 − r_s / r
dt/dλ = E / f

d²r/dλ²  = −(r_s / 2r²) · f · (dt/dλ)²
          + (r_s / 2r²f) · (dr/dλ)²
          + r · ((dθ/dλ)² + sin²(θ) · (dφ/dλ)²)

d²θ/dλ²  = −2 · (dr/dλ)(dθ/dλ) / r
          + sin(θ)cos(θ) · (dφ/dλ)²

d²φ/dλ²  = −2 · (dr/dλ)(dφ/dλ) / r
          − 2 · cos(θ)/sin(θ) · (dθ/dλ)(dφ/dλ)
```

**Source:** `geodesicRHS()` in both `geodesic.comp` and `CPU-geodesic.cpp`

### 5.2 2D Schwarzschild Null Geodesic (Equatorial Plane)

State vector: `y = (r, φ, dr/dλ, dφ/dλ)`

```
f = 1 − r_s / r
dt/dλ = E / f

d²r/dλ²  = −(r_s / 2r²) · f · (dt/dλ)²
          + (r_s / 2r²f) · (dr/dλ)²
          + (r − r_s) · (dφ/dλ)²

d²φ/dλ²  = −2 · (dr/dλ)(dφ/dλ) / r
```

**Source:** `geodesicRHS()` in `2D_lensing.cpp`

> **Note:** The radial acceleration term `(r − r_s) · dphi²` in 2D is equivalent to `r · dphi²` in the 3D version when θ = π/2 (equatorial), since `r · sin²(π/2) · dphi² = r · dphi²`, and the extra `−r_s · dphi²` arises from the specific form of the effective potential in the equatorial reduction.

---

## 6. RK4 Integration

### 6.1 Full 4th-Order Runge-Kutta (CPU)

Used in `CPU-geodesic.cpp` and `2D_lensing.cpp` for accurate integration:

```
Given state y_n and step size h (= dλ):

k1 = f(y_n)
k2 = f(y_n + h/2 · k1)
k3 = f(y_n + h/2 · k2)
k4 = f(y_n + h · k3)

y_{n+1} = y_n + (h/6) · (k1 + 2·k2 + 2·k3 + k4)
```

Where `f()` is `geodesicRHS()` evaluated on a temporary Ray state.

**Implementation detail:** The CPU version packs the state into a flat array `y0[6]` (3D) or `y0[4]` (2D), evaluates the RHS into `k1..k4` arrays, and uses an `addState()` helper:

```
addState(a, b, factor, out):
    for i in 0..N:
        out[i] = a[i] + b[i] * factor
```

**Source:** `rk4Step()` in `CPU-geodesic.cpp` (6-component), `2D_lensing.cpp` (4-component)

### 6.2 Euler Step (GPU Compute Shader)

The compute shader (`geodesic.comp`) uses a **forward Euler** method for performance (despite the function being named `rk4Step`):

```
y_{n+1} = y_n + dL · f(y_n)
```

This trades accuracy for throughput — each ray runs 60,000 steps with small `dλ = 1e7`, which compensates for the lower-order method.

**Source:** `rk4Step()` in `geodesic.comp`

> **Migration note:** Both targets should implement full RK4. Metal compute and wgpu compute shaders have enough performance headroom; the Euler shortcut was a development simplification, not a necessary optimization.

---

## 7. Integration Parameters

| Parameter | `geodesic.comp` (GPU) | `CPU-geodesic.cpp` | `2D_lensing.cpp` |
|-----------|----------------------|---------------------|-------------------|
| `D_LAMBDA` (step size) | `1e7` | `1e7` | `1.0` |
| `MAX_STEPS` | `60,000` | `10,000` | per-frame (continuous) |
| `ESCAPE_R` (termination radius) | `1e30` | `1e14` | — |

### Termination Conditions

A ray stops marching when any of these are true:
1. **Black hole capture:** `r ≤ r_s` (inside event horizon)
2. **Escape to infinity:** `r > ESCAPE_R`
3. **Disk hit:** ray crosses equatorial plane within disk bounds (GPU only)
4. **Object hit:** ray enters an object's bounding sphere (GPU only)
5. **Step limit reached**

---

## 8. Accretion Disk Model

The accretion disk is a thin annular ring in the equatorial plane (y=0 in world coordinates, or θ=π/2 in spherical).

### Parameters

```
disk_inner_radius = r_s × 2.2
disk_outer_radius = r_s × 5.2
disk_thickness    = 1e9 m
```

### Detection

A disk hit is detected when a ray **crosses the equatorial plane** (sign change in y-coordinate) AND the crossing point lies within the disk radii:

```
crossed = (oldPos.y × newPos.y < 0)
r_cross = length(vec2(newPos.x, newPos.z))
hit     = crossed AND (disk_r1 ≤ r_cross ≤ disk_r2)
```

**Source:** `crossesEquatorialPlane()` in `geodesic.comp`

### Disk Coloring

```
r_normalized = length(hitPos) / disk_outer_radius
diskColor    = vec3(1.0, r_normalized, 0.2)
alpha        = r_normalized
```

This produces a gradient from orange-red (inner edge) to yellow-white (outer edge).

---

## 9. N-Body Gravity Simulation

Simple pairwise Newtonian gravity between scene objects (stars + black hole). Used for the interactive gravity mode (`G` key toggle).

```
for each pair (obj_i, obj_j) where i ≠ j:
    Δ     = obj_j.pos − obj_i.pos
    dist  = |Δ|
    dir   = Δ / dist

    F     = G · m_i · m_j / dist²
    a_i   = F / m_i = G · m_j / dist²

    obj_i.velocity += dir · a_i
    obj_i.position += obj_i.velocity
```

> **Note:** This is a simple Euler integration without `dt` scaling — velocity accumulates per frame. A proper implementation should multiply by `dt` (frame delta time).

**Source:** main loop in `black_hole.cpp`

---

## 10. Spacetime Curvature Grid (Flamm's Paraboloid)

The grid overlay visualizes spacetime curvature using **Flamm's paraboloid** embedding of the Schwarzschild geometry.

For each grid vertex at position `(worldX, worldZ)`:

```
for each massive object:
    r_s  = 2GM / c²
    dist = sqrt((worldX − objX)² + (worldZ − objZ)²)

    if dist > r_s:
        y += 2 · sqrt(r_s · (dist − r_s)) − 3e10
    else:
        y += 2 · sqrt(r_s²) − 3e10     // deep pit inside horizon
```

### Grid Parameters

```
gridSize = 25 × 25 vertices
spacing  = 1e10 m between vertices
offset   = 3e10 m (vertical shift to center the paraboloid)
```

Rendered as `GL_LINES` with translucent gray color `(0.5, 0.5, 0.5, 0.7)`.

**Source:** `generateGrid()` in `black_hole.cpp`, `grid.vert`, `grid.frag`

---

## 11. Camera Model

Orbit camera centered on the black hole at the origin.

### Spherical Orbit Parameters

```
position.x = radius · sin(elevation) · cos(azimuth)
position.y = radius · cos(elevation)
position.z = radius · sin(elevation) · sin(azimuth)

target = (0, 0, 0)   // always looking at black hole center
```

### Default Values

| Parameter | `black_hole.cpp` | `CPU-geodesic.cpp` |
|-----------|-------------------|---------------------|
| `radius` | `6.34194e10` | `6.34194e10` |
| `minRadius` | `1e10` | `1e12` |
| `maxRadius` | `1e12` | `1e20` |
| `azimuth` | `0.0` | `0.0` |
| `elevation` | `π/2` | `π/2` |
| `orbitSpeed` | `0.01` | `0.008` |
| `zoomSpeed` | `25e9` (additive) | `1.08` (multiplicative) |
| `FOV` | `60°` | `60°` |

### View Construction (for ray generation)

```
forward  = normalize(target − position)
right    = normalize(cross(forward, (0, 1, 0)))
up       = cross(right, forward)

tanHalfFov = tan(FOV/2 · π/180)
aspect     = windowWidth / windowHeight
```

### Ray Direction from Pixel

```
u   = (2 · (px + 0.5) / width − 1) · aspect · tanHalfFov
v   = (1 − 2 · (py + 0.5) / height) · tanHalfFov
dir = normalize(u · right − v · up + forward)
```

> **Note:** The `−v` convention flips the y-axis so that pixel (0,0) is top-left.

**Source:** `uploadCameraUBO()` and `dispatchCompute()` in `black_hole.cpp`, `main()` shader in `geodesic.comp`

---

## 12. Object Intersection Tests

### 12.1 Black Hole Event Horizon

Simple distance check against Schwarzschild radius:

```
hit = (ray.r ≤ r_s)
```

Or equivalently in Cartesian:
```
dist² = (px − bh.x)² + (py − bh.y)² + (pz − bh.z)²
hit   = dist² < r_s²
```

### 12.2 Scene Object (Sphere) Intersection

Distance-based bounding sphere test in the geodesic march:

```
hit = distance(rayPos, objectCenter) ≤ objectRadius
```

**Source:** `interceptObject()` in `geodesic.comp`

### 12.3 Analytic Ray-Sphere (Classic Ray Tracing)

Quadratic formula for exact ray-sphere intersection:

```
oc   = ray.origin − sphere.center
a    = dot(dir, dir)
b    = 2 · dot(oc, dir)
c    = dot(oc, oc) − radius²
disc = b² − 4ac

if disc < 0: no hit
t = (−b − sqrt(disc)) / (2a)    // nearest intersection
if t < 0: t = (−b + sqrt(disc)) / (2a)
```

**Source:** `Object::Intersect()` in `ray_tracing.cpp`

---

## 13. Shading Models

### 13.1 Geodesic Object Shading (Compute Shader)

View-dependent diffuse with ambient:

```
N         = normalize(hitPoint − objectCenter)
V         = normalize(camPos − hitPoint)
ambient   = 0.1
diff      = max(dot(N, V), 0.0)
intensity = ambient + (1 − ambient) · diff
color     = objectColor.rgb · intensity
```

**Source:** hit-object branch in `geodesic.comp`

### 13.2 Classic Ray Tracing Shading

Diffuse lighting with shadow rays:

```
N        = normalize(hitPoint − sphereCenter)
lightDir = normalize(lightPos − hitPoint)
diff     = max(dot(N, lightDir), 0.0)

// Shadow test: cast ray from hitPoint toward light
shadowRay.origin = hitPoint + N · 0.001   // offset to avoid self-intersection
if any object intersects shadowRay:
    color = baseColor · 0.1               // ambient only
else:
    color = baseColor · (0.1 + diff · 0.9)
```

Default light position: `(5, 5, 5)`

**Source:** `Scene::trace()` in `ray_tracing.cpp`

---

## 14. Scene Objects (Default Configuration)

```
objects = [
    { pos: (4e11, 0, 0),   radius: 4e10,  color: yellow (1,1,0), mass: 1.98892e30 },  // Star 1
    { pos: (0, 0, 4e11),   radius: 4e10,  color: red (1,0,0),    mass: 1.98892e30 },  // Star 2
    { pos: (0, 0, 0),      radius: r_s,   color: black (0,0,0),  mass: 8.54e36 },     // Sag A*
]
```

---

## 15. Rendering Pipeline Summary

### GPU Path (`black_hole.cpp` + `geodesic.comp`)

1. **Compute pass:** Dispatch `ceil(W/16) × ceil(H/16)` workgroups of 16×16 threads
2. Each thread: generate ray → march 60,000 Euler steps → write RGBA to output texture
3. Memory barrier (`GL_SHADER_IMAGE_ACCESS_BARRIER_BIT`)
4. **Grid pass:** CPU-generated Flamm's paraboloid mesh → draw as `GL_LINES`
5. **Quad pass:** fullscreen quad textured with compute output → present

### CPU Path (`CPU-geodesic.cpp`)

1. For each pixel: generate ray → march up to 10,000 RK4 steps
2. Write RGB to pixel buffer
3. Upload pixel buffer as texture → draw fullscreen quad → present

### Compute Resolution

| Mode | Width | Height |
|------|-------|--------|
| Default | 200 | 150 |
| Camera moving | 200 | 150 |

Window size is `800 × 600`; the compute output is upscaled via bilinear texture filtering.

---

## 16. UBO / Buffer Layout (for shader binding)

### Camera UBO (binding = 1, std140)

```
struct CameraUBO {
    vec3 camPos;       float _pad0;    // offset  0
    vec3 camRight;     float _pad1;    // offset 16
    vec3 camUp;        float _pad2;    // offset 32
    vec3 camForward;   float _pad3;    // offset 48
    float tanHalfFov;                  // offset 64
    float aspect;                      // offset 68
    bool  moving;                      // offset 72
    int   _pad4;                       // offset 76
};                                     // total: 80 bytes
```

### Disk UBO (binding = 2, std140)

```
struct DiskUBO {
    float disk_r1;      // inner radius
    float disk_r2;      // outer radius
    float disk_num;     // number of rays (unused in current shader)
    float thickness;    // disk thickness
};                      // total: 16 bytes
```

### Objects UBO (binding = 3, std140)

```
struct ObjectsUBO {
    int   numObjects;
    float _pad0, _pad1, _pad2;    // pad to 16 bytes
    vec4  posRadius[16];          // xyz = position, w = radius
    vec4  color[16];              // rgba
    float mass[16];
};
```

---

## 17. Key Numerical Considerations for Migration

1. **Floating-point precision:** The geodesic integration spans scales from `~1e10 m` (Schwarzschild radius) to `~1e30 m` (escape distance). Both MSL and WGSL use IEEE 754 `float32` by default. Consider using `float` for GPU shaders (matching current GLSL behavior) but `double` for CPU fallback paths.

2. **Singularity guards:**
   - `sin(θ)` appears in denominators (`dφ/dλ` and `d²φ/dλ²`). Clamp `θ` away from 0 and π.
   - `f(r) = 1 − r_s/r` appears in denominators. Stop integration when `r ≤ r_s`.
   - `r` appears in many denominators. The `r ≤ r_s` check prevents division by zero.

3. **Euler vs RK4:** The GPU shader currently uses Euler. Migrated versions should implement full RK4 for better accuracy at the same step count, or use Euler with the same high step count for equivalent visual results.

4. **Coordinate convention:** Y is up in world space. The accretion disk lies in the XZ plane (y=0). This maps to θ=π/2 in spherical coordinates.
