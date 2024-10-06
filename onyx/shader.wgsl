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
	paint: u32,
};

struct Prims {
	prims: array<Prim>,
};

@group(2)
@binding(0)
var<storage> prims: Prims;

struct Paint {
	kind: u32,
	col0: vec4<f32>,
	col1: vec4<f32>,
	// image: u32,
};

struct Paints {
	paints: array<Paint>,
};

@group(2)
@binding(1)
var<storage> paints: Paints;

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

// SDF shapes
fn sd_circle(p: vec2<f32>, r: f32) -> f32 {
	return length(p) - r;
}
fn sd_box(p: vec2<f32>, b: vec2<f32>, r: f32) -> f32 {
	let d = abs(p) - b + r;
	return length(max(d, vec2<f32>(0.0, 0.0))) + min(max(d.x, d.y), 0.0) - r;
}
// uh shadows or smth
fn rounded_box_shadow_x(x: f32, y: f32, sigma: f32, corner: f32, half_size: vec2<f32>) -> f32 {
	let delta = min(half_size.y - corner - abs(y), 0.0);
	let curved = half_size.x - corner + sqrt(max(0.0, corner * corner - delta * delta));
  let integral = 0.5 + 0.5 * erf((x + vec2(-curved, curved)) * (sqrt(0.5) / sigma));
  return integral.y - integral.x;
}
fn gaussian(x: f32, sigma: f32) -> f32 {
	let pi: f32 = 3.141592653589793;
  return exp(-(x * x) / (2.0 * sigma * sigma)) / (sqrt(2.0 * pi) * sigma);
}

// This approximates the error function, needed for the gaussian integral
fn erf(x: vec2<f32>) -> vec2<f32> {
    let s = sign(x);
    let a = abs(x);
    var y = 1.0 + (0.278393 + (0.230389 + 0.078108 * (a * a)) * a) * a;
    y *= y;
    return s - s / (y * y);
}

fn sd_prim(prim: Prim, p: vec2<f32>) -> f32 {
	var d = 1e10;
	var s = 1.0;
	switch (prim.kind) {
		case 0u: {

		}
		// Circle
		case 1u: {
			d = sd_circle(p - prim.cv0, prim.radius);
		}
		// Box
		case 2u: {
			let center = 0.5 * (prim.cv0 + prim.cv1);
			d = sd_box(p - center, (prim.cv1 - prim.cv0) * 0.5, prim.radius);
		}
		// Rounded box shadow
		case 3u: {
			let blur_radius = prim.cv2.x;
      let center = 0.5*(prim.cv1 + prim.cv0);
      let half_size = 0.5*(prim.cv1 - prim.cv0);
      let point = p - center;

      let low = point.y - half_size.y;
      let high = point.y + half_size.y;
      let start = clamp(-3.0 * blur_radius, low, high);
      let end = clamp(3.0 * blur_radius, low, high);

      let step = (end - start) / 4.0;
      var y = start + step * 0.5;
      var value = 0.0;
      for (var i: i32 = 0; i < 4; i++) {
          value += rounded_box_shadow_x(point.x, point.y - y, blur_radius, prim.radius, half_size) * gaussian(y, blur_radius) * step;
          y += step;
      }
      d = (1.0 - value * 4.0);
		}
		default: {}
	}
	return max(d, 0.0);
}

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
	let prim = prims.prims[in.prim];
	let paint = paints.paints[prim.paint];

	var out: vec4<f32>;
	var alpha: f32 = 1.0;

	out = textureSample(draw_call_texture, draw_call_sampler, in.uv) * in.col;

	var d = sd_prim(prim, in.pos.xy);

	if (prim.kind > 0u) {
		out.a *= (1.0 - d);
	}

  return out;
}
