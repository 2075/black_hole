use bytemuck::{Pod, Zeroable};
use glam::Vec3;

// ─── Physical Constants ──────────────────────────────────────────────────────

pub const SPEED_OF_LIGHT: f64 = 299_792_458.0;
pub const GRAVITATIONAL_CONSTANT: f64 = 6.67430e-11;
pub const SAG_A_MASS: f64 = 8.54e36;
pub const SAG_A_RS: f64 =
    2.0 * GRAVITATIONAL_CONSTANT * SAG_A_MASS / (SPEED_OF_LIGHT * SPEED_OF_LIGHT);

pub const DISK_INNER_FACTOR: f32 = 2.2;
pub const DISK_OUTER_FACTOR: f32 = 5.2;
pub const DISK_THICKNESS: f32 = 1e9;
pub const DEFAULT_STEP_COUNT: i32 = 60_000;
pub const INTERACTION_STEP_COUNT: i32 = 5_000;
pub const WORKGROUP_SIZE: u32 = 16;
pub const BASE_COMPUTE_HEIGHT: u32 = 75;

// ─── GPU Uniform Structs ─────────────────────────────────────────────────────
// Must match WGSL struct layouts exactly.

#[repr(C)]
#[derive(Copy, Clone, Pod, Zeroable)]
pub struct CameraUniforms {
    pub cam_pos: [f32; 3],
    pub _pad0: f32,
    pub cam_right: [f32; 3],
    pub _pad1: f32,
    pub cam_up: [f32; 3],
    pub _pad2: f32,
    pub cam_forward: [f32; 3],
    pub _pad3: f32,
    pub tan_half_fov: f32,
    pub aspect: f32,
    pub moving: i32,
    pub step_count: i32,
}

#[repr(C)]
#[derive(Copy, Clone, Pod, Zeroable)]
pub struct DiskUniforms {
    pub disk_r1: f32,
    pub disk_r2: f32,
    pub disk_num: f32,
    pub thickness: f32,
    pub disk_color: [f32; 4],
}

#[repr(C)]
#[derive(Copy, Clone, Pod, Zeroable)]
pub struct ObjectsUniforms {
    pub num_objects: i32,
    pub _pad0: f32,
    pub _pad1: f32,
    pub _pad2: f32,
    pub obj_pos_radius: [[f32; 4]; 16],
    pub obj_color: [[f32; 4]; 16],
    pub mass: [f32; 16],
}

// ─── Scene Object ────────────────────────────────────────────────────────────

pub struct SceneObject {
    pub position: Vec3,
    pub radius: f32,
    pub color: [f32; 4],
    pub mass: f32,
    pub velocity: Vec3,
}

pub fn make_default_scene_objects() -> Vec<SceneObject> {
    vec![
        SceneObject {
            position: Vec3::new(4e11, 0.0, 0.0),
            radius: 4e10,
            color: [1.0, 1.0, 0.0, 1.0],
            mass: 1.98892e30,
            velocity: Vec3::ZERO,
        },
        SceneObject {
            position: Vec3::new(0.0, 0.0, 4e11),
            radius: 4e10,
            color: [1.0, 0.0, 0.0, 1.0],
            mass: 1.98892e30,
            velocity: Vec3::ZERO,
        },
        SceneObject {
            position: Vec3::ZERO,
            radius: SAG_A_RS as f32,
            color: [0.0, 0.0, 0.0, 1.0],
            mass: SAG_A_MASS as f32,
            velocity: Vec3::ZERO,
        },
    ]
}
