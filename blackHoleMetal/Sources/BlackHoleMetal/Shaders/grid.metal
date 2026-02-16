#include <metal_stdlib>
using namespace metal;

// MARK: - Grid Shaders
// Ported from grid.vert / grid.frag (GLSL 330)

struct GridVertexIn {
    float3 position [[attribute(0)]];
};

struct GridVertexOut {
    float4 position [[position]];
};

vertex GridVertexOut gridVertexShader(
    const device float3 *vertices [[buffer(0)]],
    constant float4x4 &viewProj  [[buffer(1)]],
    uint vid                      [[vertex_id]]
) {
    GridVertexOut out;
    out.position = viewProj * float4(vertices[vid], 1.0);
    return out;
}

fragment float4 gridFragmentShader(GridVertexOut in [[stage_in]]) {
    // Translucent gray lines (matches original GLSL: vec4(0.5, 0.5, 0.5, 0.7))
    return float4(0.5, 0.5, 0.5, 0.7);
}
