struct Uniforms {
  size: vec2<f32>,
  time: f32,
};

@group(0)
@binding(0)
var<uniform> uniforms: Uniforms;

struct Shape {
	kind: u32,
	cv0: vec2<f32>,
	cv1: vec2<f32>,
	cv2: vec2<f32>,
	corners: vec4<f32>,
	radius: f32,
	width: f32,
	paint: u32,
	scissor: u32,
	start: u32,
	count: u32,
	stroke: u32,
	xform: u32,
};

struct Shapes {
	shapes: array<Shape>,
};

@group(2)
@binding(0)
var<storage> shapes: Shapes;

struct Paint {
	kind: u32,
	col0: vec4<f32>,
	col1: vec4<f32>,
	xform: u32,
};

struct Paints {
	paints: array<Paint>,
};

@group(2)
@binding(1)
var<storage> paints: Paints;

struct CVS {
	cvs: array<vec2<f32>>,
};

@group(2)
@binding(2)
var<storage> cvs: CVS;

struct XForms {
	xforms: array<mat4x4<f32>>,
};

@group(2)
@binding(3)
var<storage> xforms: XForms;

struct VertexInput {
	@location(0) pos: vec2<f32>,
	@location(1) uv: vec2<f32>,
	@location(2) col: vec4<f32>,
	@location(3) shape: u32,
};

struct VertexOutput {
  @builtin(position) pos: vec4<f32>,
  @location(0) uv: vec2<f32>,
  @location(1) col: vec4<f32>,
	@location(2) shape: u32,
	@location(3) p: vec2<f32>,
};

@group(1)
@binding(0)
var atlas_samp: sampler;

@group(1)
@binding(1)
var atlas_tex: texture_2d<f32>;

@group(1)
@binding(2)
var user_samp: sampler;

@group(1)
@binding(3)
var user_tex: texture_2d<f32>;

fn sd_subtract(d1: f32, d2: f32) -> f32 {
	return max(-d1, d2);
}

fn sd_circle(p: vec2<f32>, r: f32) -> f32 {
	return length(p) - r;
}

fn sd_pie(p: vec2<f32>, sca: vec2<f32>, scb: vec2<f32>, r: f32) -> f32 {
	var pp = p * mat2x2<f32>(sca,vec2<f32>(-sca.y,sca.x));
	pp.x = abs(pp.x);
	let l = length(pp) - r;
	let m = length(pp - scb * clamp(dot(pp, scb), 0.0, r));
	return max(l, m * sign(scb.y * pp.x - scb.x * pp.y)) + 0.5;
}

fn sd_pie2(p: vec2<f32>, n: vec2<f32>) -> f32 {
	return abs(p).x * n.y + p.y * n.x;
}

fn sd_arc_square(p: vec2<f32>, sca: vec2<f32>, scb: vec2<f32>, radius: f32, width: f32) -> f32 {
	// Rotate point.
  let pp = p * mat2x2<f32>(sca,vec2<f32>(-sca.y,sca.x));
  return sd_subtract(sd_pie2(pp, vec2<f32>(scb.x, -scb.y)), abs(sd_circle(pp, radius)) - width);
}

fn sd_arc(p: vec2<f32>, sca: vec2<f32>, scb: vec2<f32>, ra: f32, rb: f32) -> f32 {
	var pp = p * mat2x2<f32>(vec2<f32>(sca.x,sca.y),vec2<f32>(-sca.y,sca.x));
  pp.x = abs(pp.x);
  var k = 0.0;
  if (scb.y*pp.x>scb.x*pp.y) {
      k = dot(pp,scb);
  } else {
      k = length(pp);
  }
  return sqrt( dot(pp,pp) + ra*ra - 2.0*ra*k ) - rb + 1;
}

fn sd_box(p: vec2<f32>, b: vec2<f32>, rr: vec4<f32>) -> f32 {
	var r: vec2<f32>;
	if (p.x > 0.0) {
		r = rr.yw;
	} else {
		r = rr.xz;
	}
	if (p.y > 0.0) {
		r.x = r.y;
	}
  let q = abs(p) - b + r.x;
  return min(max(q.x, q.y), 0.0) + length(max(q, vec2<f32>(0.0, 0.0))) - r.x + 0.5;
}

fn sd_bezier_approx(p: vec2<f32>, A: vec2<f32>, B: vec2<f32>, C: vec2<f32>) -> f32 {
  let v0 = normalize(B - A); let v1 = normalize(C - A);
  let det = v0.x * v1.y - v1.x * v0.y;
  if(abs(det) < 0.01) {
    return sd_bezier(p, A, B, C);
  }
  return length(get_distance_vector(A-p, B-p, C-p));
}

fn sd_bezier(pos: vec2<f32>, A: vec2<f32>, B: vec2<f32>, C: vec2<f32> ) -> f32 {
  let a = B - A;
  let b = A - 2.0*B + C;
  let c = a * 2.0;
  let d = A - pos;
  let kk = 1.0/dot(b,b);
  let kx = kk * dot(a,b);
  let ky = kk * (2.0*dot(a,a)+dot(d,b)) / 3.0;
  let kz = kk * dot(d,a);
  var res = 0.0;
  let p = ky - kx*kx;
  let p3 = p*p*p;
  let q = kx*(2.0*kx*kx + -3.0*ky) + kz;
  var h = q*q + 4.0*p3;
  if (h >= 0.0) {
    h = sqrt(h);
    let x = (vec2<f32>(h,-h)-q)/2.0;
    let uv = sign(x)*pow(abs(x), vec2<f32>(1.0/3.0));
    let t = clamp( uv.x+uv.y-kx, 0.0, 1.0 );
    res = dot2(d + (c + b*t)*t);
  } else {
    let z = sqrt(-p);
    let v = acos( q/(p*z*2.0) ) / 3.0;
    let m = cos(v);
    let n = sin(v)*1.732050808;
    let t = clamp(vec3<f32>(m+m,-n-m,n-m)*z-kx, vec3<f32>(0.0), vec3<f32>(1.0));
    res = min( dot2(d+(c+b*t.x)*t.x),
                dot2(d+(c+b*t.y)*t.y) );
    // the third root cannot be the closest
    // res = min(res,dot2(d+(c+b*t.z)*t.z));
  }
  return sqrt( res );
}

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

fn dot2(v: vec2<f32>) -> f32 {
    return dot(v, v);
}

fn get_distance_vector(b0: vec2<f32>, b1: vec2<f32>, b2: vec2<f32>) -> vec2<f32> {

    let a = det(b0, b2);
    let b = 2.0 * det(b1, b0);
    let d = 2.0 * det(b2, b1);

    let f = b * d - a * a;
    let d21 = b2 - b1; let d10 = b1 - b0; let d20 = b2 - b0;
    var gf = 2.0 * (b * d21 + d * d10 + a * d20);
    gf = vec2<f32>(gf.y, -gf.x);
    let pp = -f * gf / dot(gf, gf);
    let d0p = b0 - pp;
    let ap = det(d0p, d20); let bp = 2.0 * det(d10, d0p);
    // (note that 2*ap+bp+dp=2*a+b+d=4*area(b0,b1,b2))
    let t = clamp((ap + bp) / (2.0 * a + b + d), 0.0, 1.0);
    return mix(mix(b0, b1, t), mix(b1, b2, t), t);
}

fn det(a: vec2<f32>, b: vec2<f32>) -> f32 { return a.x * b.y - b.x * a.y; }

fn erf(x: vec2<f32>) -> vec2<f32> {
    let s = sign(x);
    let a = abs(x);
    var y = 1.0 + (0.278393 + (0.230389 + 0.078108 * (a * a)) * a) * a;
    y *= y;
    return s - s / (y * y);
}

fn lineTest(p: vec2<f32>, A: vec2<f32>, B: vec2<f32>) -> bool {
  let cs = i32(A.y < p.y) * 2 + i32(B.y < p.y);
  if(cs == 0 || cs == 3) { return false; } // trivial reject
  let v = B - A;
  // Intersect line with x axis.
  let t = (p.y - A.y) / v.y;
  return (A.x + t*v.x) > p.x;
}

fn bezierTest(p: vec2<f32>, A: vec2<f32>, B: vec2<f32>, C: vec2<f32>) -> bool {
  // Compute barycentric coordinates of p.
  // p = s * A + t * B + (1-s-t) * C
  let v0 = B - A; let v1 = C - A; let v2 = p - A;
  let det = v0.x * v1.y - v1.x * v0.y;
  let s = (v2.x * v1.y - v1.x * v2.y) / det;
  let t = (v0.x * v2.y - v2.x * v0.y) / det;
  if(s < 0.0 || t < 0.0 || (1.0-s-t) < 0.0) {
    return false; // outside triangle
  }
  // Transform to canonical coordinte space.
  let u = s * 0.5 + t;
  let v = t;
  return u * u < v;
}

fn sd_shape(shape: Shape, p: vec2<f32>) -> f32 {
	var d = 1e10;
	switch (shape.kind) {
		case 0u: {

		}
		// Circle
		case 1u: {
			d = sd_circle(p - shape.cv0, shape.radius) + 1;
		}
		// Box
		case 2u: {
			let center = 0.5 * (shape.cv0 + shape.cv1);
			d = sd_box(p - center, (shape.cv1 - shape.cv0) * 0.5, shape.corners);
		}
		// Rounded box shadow
		case 3u: {
			let blur_radius = shape.cv2.x;
			let center = 0.5*(shape.cv1 + shape.cv0);
			let half_size = 0.5*(shape.cv1 - shape.cv0);
      let point = p - center;

      let low = point.y - half_size.y;
      let high = point.y + half_size.y;
      let start = clamp(-3.0 * blur_radius, low, high);
      let end = clamp(3.0 * blur_radius, low, high);

      let step = (end - start) / 4.0;
      var y = start + step * 0.5;
      var value = 0.0;
      for (var i: i32 = 0; i < 4; i++) {
          value += rounded_box_shadow_x(point.x, point.y - y, blur_radius, shape.radius, half_size) * gaussian(y, blur_radius) * step;
          y += step;
      }
      d = (1.0 - value * 4.0);
		}
		// Arc
		case 4u: {
			d = sd_arc(p - shape.cv0, shape.cv1, shape.cv2, shape.radius, shape.width);
		}
		// Bezier
		case 5u: {
			d = sd_bezier(p, shape.cv0, shape.cv1, shape.cv2) + 1.0 - shape.width;
		}
		// Pie
		case 6u: {
			d = sd_pie(p - shape.cv0, shape.cv1, shape.cv2, shape.radius);
		}
		// Quad Path
		case 7u: {
			var s = 1.0;
			let filterWidth = 1.0;
      for(var i = 0; i < i32(shape.count); i = i + 1) {
      	let j = i32(shape.start) + 3 * i;
        let a = cvs.cvs[j];
        let b = cvs.cvs[j + 1];
        let c = cvs.cvs[j + 2];
        var skip = false;
        let xmax = p.x + filterWidth;
        let xmin = p.x - filterWidth;
        // If the hull is far enough away, don't bother with
        // a sdf.
        if(a.x > xmax && b.x > xmax && c.x > xmax) {
          skip = true;
        } else if(a.x < xmin && b.x < xmin && c.x < xmin) {
          skip = true;
        }
        if(!skip) {
          d = min(d, sd_bezier(p, a, b, c));
        }
        if(lineTest(p, a, c)) {
          s = -s;
        }
        // Flip if inside area between curve and line.
        if(!skip) {
          if(bezierTest(p, a, b, c)) {
            s = -s;
          }
        }
      }
      d = d * s + 1;
    }
    // Arbitrary Polygon
    case 8u {
   		var d = dot(p - cvs.cvs[0], p - cvs.cvs[0]);
     	var s = 1.0;
      for(var i: u32 = 0; i < shape.count; i += 1u) {
      	let j = (i + 1) % shape.count;
      	let ii = i + shape.start;
       	let jj = j + shape.start;
        let e = cvs.cvs[jj] - cvs.cvs[ii];
        let w = p - cvs.cvs[ii];
        let b = w - e * clamp(dot(w, e) / dot(e, e), 0.0, 1.0);
        d = min(d, dot(b, b));
        let c = vec3<bool>(p.y >= cvs.cvs[ii].y, p.y < cvs.cvs[jj].y, e.x * w.y > e.y * w.x);
        if(all(c) || all(not(c))) {
        	 s *= -1.0;
        }
      }
      return s * sqrt(d) + 0.5;
    }
		default: {}
	}
	if (shape.stroke != 0u) {
		d = abs(d) - shape.width / 2 + 0.5;
	}
	return d;
}

fn not(v: vec3<bool>) -> vec3<bool> {
	return vec3<bool>(!v.x, !v.y, !v.z);
}

fn hash(p: vec2<f32>) -> vec2<f32> {
	var pp = vec2<f32>( dot(p,vec2<f32>(127.1,311.7)), dot(p,vec2<f32>(269.5,183.3)) );
	return -1.0 + 2.0*fract(sin(pp)*43758.5453123);
}

fn noise(p: vec2<f32>) -> f32 {
  let K1: f32 = 0.366025404; // (sqrt(3)-1)/2;
  let K2: f32 = 0.211324865; // (3-sqrt(3))/6;

	let i: vec2<f32> = floor(p + (p.x + p.y) * K1);
  let a: vec2<f32> = p - i + (i.x + i.y) * K2;
  let m: f32 = step(a.y, a.x);
  let o: vec2<f32> = vec2(m, 1.0 - m);
  let b: vec2<f32> = a - o + K2;
	let c: vec2<f32> = a - 1.0 + 2.0 * K2;
  let h: vec3<f32> = max(vec3<f32>(0.5) - vec3<f32>(dot2(a), dot2(b), dot2(c)), vec3<f32>(0.0));
	let n: vec3<f32> = h * h * h * h * vec3(dot(a, hash(i + 0.0)), dot(b, hash(i+o)), dot(c, hash(i + 1.0)));
  return dot(n, vec3<f32>(70.0));
}

@vertex
fn vs_main(in: VertexInput) -> VertexOutput {
	let xform = xforms.xforms[shapes.shapes[in.shape].xform];
  var pos = (xform * vec4<f32>(in.pos, 0.0, 1.0)).xy;
  pos = vec2<f32>(2.0, -2.0) * pos / uniforms.size + vec2<f32>(-1.0, 1.0);
  var out: VertexOutput;
  out.p = in.pos;
  out.pos = vec4<f32>(pos, 0.0, 1.0);
  out.uv = in.uv;
  out.col = in.col;
  out.shape = in.shape;
  return out;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
	let shape = shapes.shapes[in.shape];
	let paint = paints.paints[shape.paint];

	var out: vec4<f32>;
	var alpha: f32 = 1.0;

	var d = 0.0;

	if (shape.kind > 0u) {
		d = sd_shape(shape, in.p);
	}

	if (shape.scissor > 0u) {
		d = max(d, sd_shape(shapes.shapes[shape.scissor], in.p));
	}

	// Get pixel color
	switch (paint.kind) {
		// Glyph
		case 1u: {
			out = textureSample(atlas_tex, atlas_samp, in.uv) * in.col;
			out.a *= 1.0 + 0.25 * out.r;
		}
		// User_Image
		case 2u: {
			out = textureSampleBias(user_tex, user_samp, in.uv, -0.5) * in.col;
		}
		// Skeleton
		case 3u: {
			var uv = in.p;
			var f = 0.5 * noise(uv * 0.0025 + uniforms.time * 0.2);
			uv = mat2x2<f32>(1.6, 1.2, -1.2, 1.6) * uv;
			f += 0.5 * noise(uv * 0.0025 - uniforms.time * 0.2);
			// out = (paint.col0 + (paint.col1 - paint.col0) * f) * in.col;
			out = vec4<f32>(1.0, 1.0, 1.0, clamp(f, 0.0, 1.0)) * in.col;
		}
		// Gradient
		case 4u: {
	    let d = clamp((xforms.xforms[paint.xform] * vec4<f32>(in.p, 0.0, 1.0)).y, 0.0, 1.0);
	    out = mix(paint.col0, paint.col1, d) * in.col;
		}
		default: {
			out = in.col;
		}
	}

	out.a *= (1.0 - max(d, 0.0));

  return out;
}
