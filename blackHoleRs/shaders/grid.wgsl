// Grid shaders — port of grid.vert / grid.frag (GLSL 330 → WGSL)
// Renders spacetime curvature grid lines as translucent overlay.

struct GridUniforms {
    view_proj: mat4x4f,
};

@group(0) @binding(0) var<uniform> grid_uniforms: GridUniforms;

struct VertexOutput {
    @builtin(position) position: vec4f,
};

@vertex
fn vs_main(@location(0) pos: vec3f) -> VertexOutput {
    var out: VertexOutput;
    out.position = grid_uniforms.view_proj * vec4f(pos, 1.0);
    return out;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4f {
    return vec4f(0.5, 0.5, 0.5, 0.7);
}
