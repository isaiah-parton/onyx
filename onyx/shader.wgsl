struct Uniforms {
    projectionMatrix: mat4x4f,
}
struct VertexInput {
    @location(0) pos: vec2<f32>,
    @location(1) uv: vec2<f32>,
    @location(2) col: vec4<f32>,
}; 
struct VertexOutput {
    @builtin(position) pos: vec4<f32>,
    @location(0) uv: vec2<f32>,
    @location(1) col: vec4<f32>,
};

@group(0) @binding(0) var<uniform> uniforms: Uniforms;
@group(1) @binding(0) var draw_call_sampler: sampler;
@group(1) @binding(1) var draw_call_texture: texture_2d<f32>;

@vertex
fn vs_main(in: VertexInput) -> VertexOutput {
    var out: VertexOutput;
    out.pos = uniforms.projectionMatrix * vec4f(in.pos.xy, 0.0, 1.0);
    out.uv = in.uv;
    out.col = in.col;
    return out;
}

@fragment
fn fs_main(@location(0) in_uv: vec2f,
           @location(1) in_col: vec4f) -> @location(0) vec4f {
    return textureSample(draw_call_texture, draw_call_sampler, in_uv) * in_col;
}