use crate::black_hole::{SceneObject, GRAVITATIONAL_CONSTANT};

/// CPU-side N-body gravity simulation.
/// Ported from the gravity loop in black_hole.cpp main().
pub struct GravitySim {
    pub is_enabled: bool,
}

impl Default for GravitySim {
    fn default() -> Self {
        Self { is_enabled: false }
    }
}

impl GravitySim {
    /// Advance all objects by one frame using pairwise Newtonian gravity.
    pub fn step(&self, objects: &mut [SceneObject], _dt: f32) {
        if !self.is_enabled {
            return;
        }

        let g = GRAVITATIONAL_CONSTANT as f32;
        let count = objects.len();

        // Collect accelerations first to avoid borrow issues
        let mut accels = vec![glam::Vec3::ZERO; count];
        for i in 0..count {
            for j in 0..count {
                if i == j {
                    continue;
                }
                let delta = objects[j].position - objects[i].position;
                let dist = delta.length();
                if dist <= 0.0 {
                    continue;
                }
                let direction = delta / dist;
                let force = (g * objects[i].mass * objects[j].mass) / (dist * dist);
                let acceleration = force / objects[i].mass;
                accels[i] += direction * acceleration;
            }
        }

        for (i, acc) in accels.iter().enumerate() {
            objects[i].velocity += *acc;
            objects[i].position += objects[i].velocity;
        }
    }
}
