// Fullscreen quad shaders — port of inline GLSL 330 → WGSL
// Draws a textured quad displaying the geodesic compute output.

struct VertexOutput {
    @builtin(position) position: vec4f,
    @location(0) tex_coord: vec2f,
};

@vertex
fn vs_main(@location(0) pos: vec2f, @location(1) uv: vec2f) -> VertexOutput {
    var out: VertexOutput;
    out.position = vec4f(pos, 0.0, 1.0);
    out.tex_coord = uv;
    return out;
}

@group(0) @binding(0) var tex: texture_2d<f32>;
@group(0) @binding(1) var tex_sampler: sampler;

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4f {
    return textureSample(tex, tex_sampler, in.tex_coord);
}
