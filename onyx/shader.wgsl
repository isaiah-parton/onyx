struct Uniforms {
    projection_matrix: mat4x4f,
}
struct VertexOutput {
    @builtin(position) clip_position: vec4<f32>,
    @location(0) uv: vec2<f32>,
    @location(1) col: vec4<f32>,
};

@group(0) @binding(0) var<uniform> uniforms: Uniforms;
@group(1) @binding(0) var draw_call_sampler: sampler;
@group(1) @binding(1) var draw_call_texture: texture_2d<f32>;

@vertex
fn vs_main(
		@location(0) in_pos: vec2<f32>,
		@location(1) in_uv: vec2<f32>,
		@location(2) in_col: vec4<f32>,
) -> VertexOutput {
    var out: VertexOutput;
    out.clip_position = vec4<f32>(in_pos, 0.0, 1.0);
    out.uv = in_uv;
    out.col = in_col;
    return out;
}

@fragment
fn fs_main(@location(0) in_uv: vec2f,
           @location(1) in_col: vec4f) -> @location(0) vec4f {
    return textureSample(draw_call_texture, draw_call_sampler, in_uv) * in_col;
}
