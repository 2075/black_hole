use glam::{Mat4, Vec3};

/// Orbit camera centered on the black hole at the origin.
/// Ported from Camera in black_hole.cpp and the Swift Camera.swift.
pub struct Camera {
    /// Look-at target (always the black hole center)
    pub target: Vec3,
    /// Orbit distance from target (meters)
    pub radius: f32,
    pub min_radius: f32,
    pub max_radius: f32,
    /// Horizontal angle (radians)
    pub azimuth: f32,
    /// Vertical angle (radians, 0 = north pole, pi = south pole)
    pub elevation: f32,

    pub orbit_speed: f32,
    pub zoom_speed: f64,

    /// True while the left mouse button is held
    pub is_dragging: bool,
    /// True for one frame after any camera mutation (scroll, key, drag)
    pub is_moving: bool,
    /// Dirty flag: set by every mutation, cleared by the renderer after dispatch
    pub has_changed: bool,

    pub last_mouse: [f64; 2],

    /// Auto-rotation state
    pub auto_rotate: bool,
    pub auto_rotate_speed: f32,
}

impl Default for Camera {
    fn default() -> Self {
        Self {
            target: Vec3::ZERO,
            radius: 6.34194e10,
            min_radius: 1e10,
            max_radius: 1e12,
            azimuth: 0.0,
            elevation: std::f32::consts::FRAC_PI_2,
            orbit_speed: 0.01,
            zoom_speed: 25e9,
            is_dragging: false,
            is_moving: false,
            has_changed: true,
            last_mouse: [0.0; 2],
            auto_rotate: false,
            auto_rotate_speed: 0.005,
        }
    }
}

impl Camera {
    /// Camera world-space position computed from spherical coordinates.
    pub fn position(&self) -> Vec3 {
        let e = self.elevation.clamp(0.01, std::f32::consts::PI - 0.01);
        Vec3::new(
            self.radius * e.sin() * self.azimuth.cos(),
            self.radius * e.cos(),
            self.radius * e.sin() * self.azimuth.sin(),
        )
    }

    pub fn forward(&self) -> Vec3 {
        (self.target - self.position()).normalize()
    }

    pub fn right(&self) -> Vec3 {
        self.forward().cross(Vec3::Y).normalize()
    }

    pub fn up(&self) -> Vec3 {
        self.right().cross(self.forward())
    }

    pub fn tan_half_fov(&self) -> f32 {
        (std::f32::consts::PI / 6.0).tan() // tan(30 deg) for 60 deg FOV
    }

    /// Build the view-projection matrix for the grid overlay.
    pub fn view_proj(&self, aspect: f32) -> Mat4 {
        let view = Mat4::look_at_rh(self.position(), self.target, Vec3::Y);
        let proj = Mat4::perspective_rh(
            std::f32::consts::PI / 3.0,
            aspect,
            1e9,
            1e14,
        );
        proj * view
    }

    pub fn clear_changed(&mut self) {
        self.has_changed = false;
    }

    pub fn clear_moving(&mut self) {
        self.is_moving = false;
    }

    // --- Input handlers ---

    pub fn on_mouse_press(&mut self, x: f64, y: f64) {
        self.is_dragging = true;
        self.is_moving = true;
        self.has_changed = true;
        self.last_mouse = [x, y];
    }

    pub fn on_mouse_release(&mut self) {
        self.is_dragging = false;
    }

    pub fn on_mouse_drag(&mut self, x: f64, y: f64) {
        let dx = (x - self.last_mouse[0]) as f32;
        let dy = (y - self.last_mouse[1]) as f32;
        self.azimuth += dx * self.orbit_speed;
        self.elevation -= dy * self.orbit_speed;
        self.elevation = self.elevation.clamp(0.01, std::f32::consts::PI - 0.01);
        self.last_mouse = [x, y];
        self.is_moving = true;
        self.has_changed = true;
    }

    pub fn on_scroll(&mut self, delta: f32) {
        self.radius -= delta * self.zoom_speed as f32;
        self.radius = self.radius.clamp(self.min_radius, self.max_radius);
        self.is_moving = true;
        self.has_changed = true;
    }

    pub fn nudge_azimuth(&mut self, delta: f32) {
        self.azimuth += delta;
        self.is_moving = true;
        self.has_changed = true;
    }

    pub fn nudge_elevation(&mut self, delta: f32) {
        self.elevation += delta;
        self.elevation = self.elevation.clamp(0.01, std::f32::consts::PI - 0.01);
        self.is_moving = true;
        self.has_changed = true;
    }

    /// Update camera state (for auto-rotation). Call once per frame.
    pub fn update(&mut self) {
        if self.auto_rotate {
            self.azimuth += self.auto_rotate_speed;
            self.has_changed = true;
        }
    }
}
