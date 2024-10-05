const prim_generic = 0;
const prim_circle = 1;
const prim_rect = 2;

struct Uniforms {
    proj_mtx: mat4x4f,
};

@group(0)
@binding(0)
var<uniform> uniforms: Uniforms;

struct Prim {
	kind: u32,
	cv0: vec2<f32>,
	cv1: vec2<f32>,
	cv2: vec2<f32>,
	radius: f32,
	image: u32,
	paint: u32,
};

@group(2)
@binding(0)
var<storage> prims: array<Prim>;

struct Paint {
	kind: u32,
};

@group(2)
@binding(1)
var<storage> paints: array<Paint>;

struct VertexInput {
	@location(0) pos: vec2<f32>,
	@location(1) uv: vec2<f32>,
	@location(2) col: vec4<f32>,
	@location(3) prim: u32,
};

struct VertexOutput {
  @builtin(position) pos: vec4<f32>,
  @location(0) uv: vec2<f32>,
  @location(1) col: vec4<f32>,
	@location(2) prim: u32,
};

@group(1) @binding(0) var draw_call_sampler: sampler;
@group(1) @binding(1) var draw_call_texture: texture_2d<f32>;

@vertex
fn vs_main(in: VertexInput) -> VertexOutput {
    var out: VertexOutput;
    out.pos = uniforms.proj_mtx * vec4<f32>(in.pos, 0.0, 1.0);
    out.uv = in.uv;
    out.col = in.col;
    out.prim = in.prim;
    return out;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
	let prim = prims[in.prim];
	let paint = paints[prim.paint];

	var out: vec4<f32>;

	switch (prim.kind) {
		case 0u: {
			out = textureSample(draw_call_texture, draw_call_sampler, in.uv) * in.col;
		}
		case 1u: {

		}
		case 2u: {

		}
		default: {

		}
	}

  return out;
}
