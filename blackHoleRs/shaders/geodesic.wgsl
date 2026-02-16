// Geodesic compute shader — port of geodesic.comp (GLSL 430 → WGSL)
// Traces null geodesics in Schwarzschild spacetime using forward-Euler integration.

// ─── Uniform Structs ─────────────────────────────────────────────────────────

struct CameraUniforms {
    cam_pos:      vec3f,
    _pad0:        f32,
    cam_right:    vec3f,
    _pad1:        f32,
    cam_up:       vec3f,
    _pad2:        f32,
    cam_forward:  vec3f,
    _pad3:        f32,
    tan_half_fov: f32,
    aspect:       f32,
    moving:       i32,
    step_count:   i32,
};

struct DiskUniforms {
    disk_r1:    f32,
    disk_r2:    f32,
    disk_num:   f32,
    thickness:  f32,
    disk_color: vec4f,
};

struct ObjectsUniforms {
    num_objects: i32,
    _pad0:       f32,
    _pad1:       f32,
    _pad2:       f32,
    obj_pos_radius: array<vec4f, 16>,
    obj_color:      array<vec4f, 16>,
    mass:           array<f32, 16>,
};

// ─── Bindings ────────────────────────────────────────────────────────────────

@group(0) @binding(0) var output: texture_storage_2d<rgba8unorm, write>;
@group(0) @binding(1) var<uniform> cam:  CameraUniforms;
@group(0) @binding(2) var<uniform> disk: DiskUniforms;
@group(0) @binding(3) var<uniform> objs: ObjectsUniforms;

// ─── Constants ───────────────────────────────────────────────────────────────

const SagA_rs:  f32 = 1.269e10;
const D_LAMBDA: f32 = 1e7;
const ESCAPE_R: f32 = 1e30;

// ─── Ray ─────────────────────────────────────────────────────────────────────

struct Ray {
    x: f32, y: f32, z: f32,
    r: f32, theta: f32, phi: f32,
    dr: f32, dtheta: f32, dphi: f32,
    E: f32, L: f32,
};

fn init_ray(pos: vec3f, dir: vec3f) -> Ray {
    var ray: Ray;
    ray.x = pos.x; ray.y = pos.y; ray.z = pos.z;
    ray.r = length(pos);
    ray.theta = acos(pos.z / ray.r);
    ray.phi = atan2(pos.y, pos.x);

    let dx = dir.x; let dy = dir.y; let dz = dir.z;
    ray.dr     = sin(ray.theta)*cos(ray.phi)*dx + sin(ray.theta)*sin(ray.phi)*dy + cos(ray.theta)*dz;
    ray.dtheta = (cos(ray.theta)*cos(ray.phi)*dx + cos(ray.theta)*sin(ray.phi)*dy - sin(ray.theta)*dz) / ray.r;
    ray.dphi   = (-sin(ray.phi)*dx + cos(ray.phi)*dy) / (ray.r * sin(ray.theta));

    ray.L = ray.r * ray.r * sin(ray.theta) * ray.dphi;
    let f = 1.0 - SagA_rs / ray.r;
    let dt_dL = sqrt((ray.dr*ray.dr)/f + ray.r*ray.r*(ray.dtheta*ray.dtheta + sin(ray.theta)*sin(ray.theta)*ray.dphi*ray.dphi));
    ray.E = f * dt_dL;

    return ray;
}

// ─── Intersection Tests ──────────────────────────────────────────────────────

fn intercept_black_hole(ray: Ray, rs: f32) -> bool {
    return ray.r <= rs;
}

struct HitInfo {
    color:  vec4f,
    center: vec3f,
    radius: f32,
    hit:    bool,
};

fn intercept_object(ray: Ray) -> HitInfo {
    var info: HitInfo;
    info.hit = false;
    info.color = vec4f(0.0);
    info.center = vec3f(0.0);
    info.radius = 0.0;
    let P = vec3f(ray.x, ray.y, ray.z);
    for (var i: i32 = 0; i < objs.num_objects; i = i + 1) {
        let center = objs.obj_pos_radius[i].xyz;
        let radius = objs.obj_pos_radius[i].w;
        if (distance(P, center) <= radius) {
            info.color = objs.obj_color[i];
            info.center = center;
            info.radius = radius;
            info.hit = true;
            return info;
        }
    }
    return info;
}

// ─── Geodesic RHS ────────────────────────────────────────────────────────────

struct GeodesicDerivs {
    d1: vec3f,
    d2: vec3f,
};

fn geodesic_rhs(ray: Ray) -> GeodesicDerivs {
    let r = ray.r;
    let theta = ray.theta;
    let dr = ray.dr;
    let dtheta = ray.dtheta;
    let dphi = ray.dphi;
    let f = 1.0 - SagA_rs / r;
    let dt_dL = ray.E / f;

    var result: GeodesicDerivs;
    result.d1 = vec3f(dr, dtheta, dphi);
    result.d2.x = -(SagA_rs / (2.0 * r * r)) * f * dt_dL * dt_dL
                + (SagA_rs / (2.0 * r * r * f)) * dr * dr
                + r * (dtheta * dtheta + sin(theta) * sin(theta) * dphi * dphi);
    result.d2.y = -2.0 * dr * dtheta / r + sin(theta) * cos(theta) * dphi * dphi;
    result.d2.z = -2.0 * dr * dphi / r - 2.0 * cos(theta) / sin(theta) * dtheta * dphi;
    return result;
}

// ─── Forward-Euler Step (matches original GPU shader) ────────────────────────

fn euler_step(ray: ptr<function, Ray>, dL: f32) {
    let derivs = geodesic_rhs(*ray);

    (*ray).r      += dL * derivs.d1.x;
    (*ray).theta  += dL * derivs.d1.y;
    (*ray).phi    += dL * derivs.d1.z;
    (*ray).dr     += dL * derivs.d2.x;
    (*ray).dtheta += dL * derivs.d2.y;
    (*ray).dphi   += dL * derivs.d2.z;

    (*ray).x = (*ray).r * sin((*ray).theta) * cos((*ray).phi);
    (*ray).y = (*ray).r * sin((*ray).theta) * sin((*ray).phi);
    (*ray).z = (*ray).r * cos((*ray).theta);
}

fn crosses_equatorial_plane(old_pos: vec3f, new_pos: vec3f, r1: f32, r2: f32) -> bool {
    let crossed = (old_pos.y * new_pos.y) < 0.0;
    let r = length(vec2f(new_pos.x, new_pos.z));
    return crossed && (r >= r1) && (r <= r2);
}

// ─── Main Compute Kernel ─────────────────────────────────────────────────────

@compute @workgroup_size(16, 16)
fn main(@builtin(global_invocation_id) gid: vec3u) {
    let dims = textureDimensions(output);
    let WIDTH  = i32(dims.x);
    let HEIGHT = i32(dims.y);

    if (i32(gid.x) >= WIDTH || i32(gid.y) >= HEIGHT) { return; }

    let u = (2.0 * (f32(gid.x) + 0.5) / f32(WIDTH)  - 1.0) * cam.aspect * cam.tan_half_fov;
    let v = (1.0 - 2.0 * (f32(gid.y) + 0.5) / f32(HEIGHT)) * cam.tan_half_fov;
    let dir = normalize(u * cam.cam_right - v * cam.cam_up + cam.cam_forward);
    var ray = init_ray(cam.cam_pos, dir);

    var color = vec4f(0.0);
    var prev_pos = vec3f(ray.x, ray.y, ray.z);

    var hit_black_hole = false;
    var hit_disk       = false;
    var hit_info: HitInfo;
    hit_info.hit = false;
    hit_info.color = vec4f(0.0);
    hit_info.center = vec3f(0.0);
    hit_info.radius = 0.0;

    let steps = cam.step_count;

    for (var i: i32 = 0; i < steps; i = i + 1) {
        if (intercept_black_hole(ray, SagA_rs)) { hit_black_hole = true; break; }
        euler_step(&ray, D_LAMBDA);

        let new_pos = vec3f(ray.x, ray.y, ray.z);
        if (crosses_equatorial_plane(prev_pos, new_pos, disk.disk_r1, disk.disk_r2)) {
            hit_disk = true;
            break;
        }
        hit_info = intercept_object(ray);
        if (hit_info.hit) { break; }
        prev_pos = new_pos;
        if (ray.r > ESCAPE_R) { break; }
    }

    if (hit_disk) {
        let r_frac = clamp(length(vec3f(ray.x, ray.y, ray.z)) / disk.disk_r2, 0.0, 1.0);
        let inner_col = disk.disk_color.rgb * 0.3;
        let outer_col = disk.disk_color.rgb;
        let disk_col = mix(inner_col, outer_col, vec3f(r_frac));
        color = vec4f(disk_col, clamp(r_frac, 0.1, 1.0));
    } else if (hit_black_hole) {
        color = vec4f(0.0, 0.0, 0.0, 1.0);
    } else if (hit_info.hit) {
        let P = vec3f(ray.x, ray.y, ray.z);
        let N = normalize(P - hit_info.center);
        let V = normalize(cam.cam_pos - P);
        let ambient = 0.1;
        let diff = max(dot(N, V), 0.0);
        let intensity = ambient + (1.0 - ambient) * diff;
        let shaded = hit_info.color.rgb * intensity;
        color = vec4f(shaded, hit_info.color.a);
    } else {
        color = vec4f(0.0);
    }

    textureStore(output, vec2u(gid.xy), color);
}
