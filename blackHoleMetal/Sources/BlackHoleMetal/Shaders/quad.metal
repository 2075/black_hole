#include <metal_stdlib>
using namespace metal;

// MARK: - Fullscreen Quad Shaders
// Ported from the inline GLSL 330 vertex/fragment shaders in Engine::CreateShaderProgram()

struct QuadVertexOut {
    float4 position [[position]];
    float2 texCoord;
};

vertex QuadVertexOut quadVertexShader(
    const device float4 *vertices [[buffer(0)]],
    uint vid                      [[vertex_id]]
) {
    // Each vertex is packed as (x, y, u, v) in a float4
    float4 v = vertices[vid];

    QuadVertexOut out;
    out.position = float4(v.xy, 0.0, 1.0);
    out.texCoord = v.zw;
    return out;
}

fragment float4 quadFragmentShader(
    QuadVertexOut in      [[stage_in]],
    texture2d<float> tex  [[texture(0)]]
) {
    constexpr sampler linearSampler(mag_filter::linear, min_filter::linear);
    return tex.sample(linearSampler, in.texCoord);
}
