package draw

import "core:fmt"
import "core:math"
import "core:math/linalg"

import sg "extra:sokol-odin/sokol/gfx"
import "extra:common"

ANGLE_TOLERANCE :: 0.1
MAX_PATH_POINTS :: 400
MAX_MATRICES :: 40
MAX_DRAW_CALLS :: 50
MAX_DRAW_CALL_TEXTURES :: 8
MAX_FONTS :: 100
MAX_ATLASES :: 8
MAX_IMAGES :: 256
ATLAS_SIZE :: 1024

Stroke_Justify :: enum {
	Inner,
	Center,
	Outer,
}

Vertex :: struct {
	pos: [3]f32,
	uv: [2]f32,
	col: [4]u8,
}

// Matrix used for vertex transforms
Matrix :: matrix[4, 4]f32

// A draw call to the GPU these are managed internally
Draw_Call :: struct {
	bindings: sg.Bindings,
	textures: [MAX_DRAW_CALL_TEXTURES]sg.Image,
	vertices: [dynamic]Vertex,
	indices: [dynamic]u16,
}

// The current rendering context
Context :: struct {
	fonts: [MAX_FONTS]Maybe(Font),
	current_font: int,

	images: [MAX_IMAGES]Maybe(Image),

	atlases: [MAX_ATLASES]Maybe(Atlas),
	current_atlas: ^Atlas,

	text_job: Text_Job,

	vertex_color: Color,
	vertex_uv: [2]f32,
	vertex_z: f32,

	draw_call_stack: common.Stack(Draw_Call, MAX_DRAW_CALLS),
	current_draw_call: ^Draw_Call,
	matrix_stack: common.Stack(Matrix, MAX_MATRICES),
	current_matrix: ^Matrix,
}

Draw_Surface :: struct {
	vertices: [dynamic]Vertex,
	indices: [dynamic]u16,
	z: f32,
}

Path :: struct {
	points: [MAX_PATH_POINTS][2]f32,
	count: int,
	closed: bool,
}

make_context :: proc() -> ^Context {
	ctx := new(Context)

	return ctx
}

color :: proc(ctx: ^Context, color: Color) {
	ctx.vertex_color = color
}

uv :: proc(ctx: ^Context, uv: [2]f32) {
	ctx.vertex_uv = uv
}

// Append a vertex and return it's index
vertex_3f32 :: proc(ctx: ^Context, x, y, z: f32) -> int {
	pos: [3]f32 = {
		ctx.current_matrix[0, 0] * x + ctx.current_matrix[0, 1] * y + ctx.current_matrix[0, 2] * z + ctx.current_matrix[0, 3],
		ctx.current_matrix[1, 0] * x + ctx.current_matrix[1, 1] * y + ctx.current_matrix[1, 2] * z + ctx.current_matrix[1, 3],
		ctx.current_matrix[2, 0] * x + ctx.current_matrix[2, 1] * y + ctx.current_matrix[2, 2] * z + ctx.current_matrix[2, 3],
	}

	return append(&ctx.current_draw_call.vertices, Vertex{
		pos = pos,
		uv = ctx.vertex_uv,
		col = ctx.vertex_color,
	})
}

vertex_2f32 :: proc(ctx: ^Context, x, y: f32) -> int {
	return vertex_3f32(ctx, x, y, ctx.vertex_z)
}

push_matrix :: proc(ctx: ^Context) {
	common.push(&ctx.matrix_stack, matrix_identity())
	ctx.current_matrix = &ctx.matrix_stack.items[ctx.matrix_stack.height - 1]
}

pop_matrix :: proc(ctx: ^Context) {
	stack.pop(&ctx.matrix_stack)
	assert(ctx.matrix_stack.height >= 1)
	ctx.current_matrix = &ctx.matrix_stack.items[ctx.matrix_stack.height - 1]
}

push_draw_call :: proc(ctx: ^Context) {
	common.push(&ctx.draw_call_stack, Draw_Call{})
	ctx.current_draw_call = &ctx.draw_call_stack.items[ctx.draw_call_stack.height - 1]
}

matrix_identity :: proc() -> Matrix {
	return {
		1, 0, 0, 0,
		0, 1, 0, 0,
		0, 0, 1, 0,
		0, 0, 0, 1,
	}
}

translate :: proc(ctx: ^Context, x, y, z: f32) {
	translation_matrix: Matrix = {
		1, 0, 0, x,
	    0, 1, 0, y,
	    0, 0, 1, z,
	    0, 0, 0, 1,
	}

	ctx.current_matrix^ *= translation_matrix
}

rotate :: proc(ctx: ^Context, angle, x, y, z: f32) {
	rotation_matrix := matrix_identity()
	
	x, y, z := x, y, z
	
	len_squared := x * x + y * y + z * z
	if len_squared != 1 && len_squared != 0 {
		inverse_len := 1 / math.sqrt(len_squared)
		x *= inverse_len
		y *= inverse_len
		z *= inverse_len
	}
	sinres := math.sin(angle)
	cosres := math.cos(angle)
	t := 1 - cosres

	rotation_matrix[0, 0] = x*x*y + cosres
	rotation_matrix[1, 0] = y*x*t - z*sinres
	rotation_matrix[2, 0] = z*x*y - y*sinres
	rotation_matrix[3, 0] = 0

	rotation_matrix[0, 1] = x*y*t - z*sinres
	rotation_matrix[1, 1] = y*y*y + cosres
	rotation_matrix[2, 1] = z*y*t + x*sinres
	rotation_matrix[3, 1] = 0

	rotation_matrix[0, 2] = x*z*t + y*sinres
	rotation_matrix[1, 2] = y*z*t + x*sinres
	rotation_matrix[2, 2] = z*z*y + cosres
	rotation_matrix[3, 2] = 0

	rotation_matrix[0, 3] = 0
	rotation_matrix[1, 3] = 0
	rotation_matrix[2, 3] = 0
	rotation_matrix[3, 3] = 1

	ctx.current_matrix^ *= rotation_matrix
}

scale :: proc(ctx: ^Context, x, y, z: f32) {
	scale_matrix: matrix[4, 4]f32 = {
		x, 0, 0, 0,
		0, y, 0, 0,
		0, 0, z, 0,
		0, 0, 0, 1,
	}

	ctx.current_matrix^ *= scale_matrix
}

present :: proc(ctx: ^Context) {
	u: Uniform = {
				texSize = core.view,
				origin = layer.box.low,
				scale = 1,
			}
			sg.apply_uniforms(.VS, 0, { 
				ptr = &u,
				size = size_of(Uniform),
			})
			sg.update_buffer(core.bindings.index_buffer, { 
				ptr = raw_data(layer.surface.indices), 
				size = u64(len(layer.surface.indices) * size_of(u16)),
			})
			sg.update_buffer(core.bindings.vertex_buffers[0], { 
				ptr = raw_data(layer.surface.vertices), 
				size = u64(len(layer.surface.vertices) * size_of(Vertex)),
			})
			sg.apply_scissor_rectf(
				u.origin.x + (layer.box.low.x - u.origin.x) * u.scale, 
				u.origin.y + (layer.box.low.y - u.origin.y) * u.scale, 
				(layer.box.high.x - layer.box.low.x) * u.scale, 
				(layer.box.high.y - layer.box.low.y) * u.scale, 
				true,
				)
			sg.draw(0, len(layer.surface.indices), 1)
			sg.apply_scissor_rectf(0, 0, core.view.x, core.view.y, true)
}

/*
// [SECTION] Paths
clear_path :: proc(path: ^Path) {
	path.count = 0
}

__get_path :: proc() -> ^Path {
	return &core.paths.items[core.paths.height - 1]
}

begin_path :: proc() {
	push(&core.paths, Path{})
}

end_path :: proc() {
	pop(&core.paths)
}

close_path :: proc() {
	__get_path().closed = true
}

point :: proc(point: [2]f32) {
	path := __get_path()
	if path.count >= MAX_PATH_POINTS {
		return
	}
	path.points[path.count] = point
	path.count += 1
}

bezier :: proc(p0, p1, p2, p3: [2]f32, segments: int) {
	step: f32 = 1.0 / f32(segments)
	for t: f32 = step; t <= 1; t += step {
		times: matrix[1, 4]f32 = {1, t, t * t, t * t * t}
		weights: matrix[4, 4]f32 = {
			1, 0, 0, 0,
			-3, 3, 0, 0,
			3, -6, 3, 0,
			-1, 3, -3, 1,
		}
		point({
			(times * weights * (matrix[4, 1]f32){p0.x, p1.x, p2.x, p3.x})[0][0],
			(times * weights * (matrix[4, 1]f32){p0.y, p1.y, p2.y, p3.y})[0][0],
		})
	}
}

arc :: proc(center: [2]f32, radius, from, to: f32) {
	da := to - from
	nsteps := int(abs(da) / ANGLE_TOLERANCE)
	for n in 1..<nsteps {
		a := from + da * f32(n) / f32(nsteps)
		point(center + {math.cos(a), math.sin(a)} * radius)
	}
}

fill_path :: proc(color: Color) {
	path := __get_path()
	if path.count < 3 {
		return
	}
	surface := __get_draw_surface()
	i := u16(len(surface.vertices))
	append(&surface.vertices, 
		Vertex{pos = path.points[0], col = color, z = surface.z},
		)
	for j in 1..<path.count {
		append(&surface.vertices, 
			Vertex{pos = path.points[j], col = color, z = surface.z},
			)
		if j < path.count - 1 {
			append(&surface.indices,
				i,
				i + u16(j),
				i + u16(j) + 1,
				)
		}
	}
}

stroke_path :: proc(thickness: f32, color: Color, justify: Stroke_Justify = .Center) {
	path := __get_path()
	if path.count < 2 {
		return
	}
	surface := __get_draw_surface()
	base_index := u16(len(surface.vertices))
	left, right: f32
	switch justify {
		case .Center:
		left = thickness / 2
		right = left
		case .Outer:
		left = thickness
		case .Inner:
		right = thickness
	}
	for i in 0..<path.count {
		a := i - 1
		b := i 
		c := i + 1
		d := i + 2
		if a < 0 {
			if path.closed {
				a = path.count - 1
			} else {
				a = 0
			}
		}
		if path.closed {
			c = c % path.count
			d = d % path.count
		} else {
			c = min(path.count - 1, c)
			d = min(path.count - 1, d)
		}
		p0 := path.points[a]
		p1 := path.points[b]
		p2 := path.points[c]
		p3 := path.points[d]
		if p1 == p2 {
			continue
		}
		line := linalg.normalize(p2 - p1)
		normal := linalg.normalize([2]f32{-line.y, line.x})
		tangent2 := line if p2 == p3 else linalg.normalize(linalg.normalize(p3 - p2) + line)
		miter2: [2]f32 = {-tangent2.y, tangent2.x}
		dot2 := linalg.dot(normal, miter2)
		// Start of segment
		if i == 0 { 
			tangent1 := line if p0 == p1 else linalg.normalize(linalg.normalize(p1 - p0) + line)
			miter1: [2]f32 = {-tangent1.y, tangent1.x}
			dot1 := linalg.dot(normal, miter1)
			__vertices(surface, 
				Vertex{pos = p1 + (right / dot1) * miter1, col = color, z = surface.z},
				Vertex{pos = p1 - (left / dot1) * miter1, col = color, z = surface.z},
			)
		}

		// End of segment
		__vertices(surface, 
			Vertex{pos = p2 + (right / dot2) * miter2, col = color, z = surface.z},
			Vertex{pos = p2 - (left / dot2) * miter2, col = color, z = surface.z},
		)
		// Join vertices
		if path.closed && i == path.count - 1 {
			// Join to first endpoint
			__indices(surface, 
				base_index + u16(i * 2), 
				base_index + u16(i * 2 + 1), 
				base_index,
				base_index + u16(i * 2 + 1),
				base_index + 1,
				base_index,
				)
		} else if i < path.count - 1 {
			// Join to next endpoint
			__indices(surface, 
				base_index + u16(i * 2),
				base_index + u16(i * 2 + 1),
				base_index + u16(i * 2 + 2),
				base_index + u16(i * 2 + 3),
				base_index + u16(i * 2 + 2),
				base_index + u16(i * 2 + 1),
				)
		}
	}
}

__join_miter :: proc(p0, p1, p2: [2]f32) -> (dot: f32, miter: [2]f32) {
	line := linalg.normalize(p2 - p1)
	normal := linalg.normalize([2]f32{-line.y, line.x})
	tangent := line if p0 == p1 else linalg.normalize(linalg.normalize(p1 - p0) + line)
	miter = {-tangent.y, tangent.x}
	dot = linalg.dot(normal, miter)
	return
}

// [SECTION] Draw surfaces
init_draw_surface :: proc(surface: ^Draw_Surface) {
	reserve(&surface.vertices, 8096)
	reserve(&surface.indices, 8096)
}

make_draw_surface :: proc() -> Draw_Surface {
	res: Draw_Surface
	init_draw_surface(&res)
	return res
}

destroy_draw_surface :: proc(surface: ^Draw_Surface) {
	delete(surface.indices)
	delete(surface.vertices)
}

clear_draw_surface :: proc(surface: ^Draw_Surface) {
	clear(&surface.vertices)
	clear(&surface.indices)
}

__get_draw_surface :: proc() -> ^Draw_Surface {
	return core.draw_surface.?
}

destroy_image :: proc(using self: ^Image) {
	delete(data)
}

__vertices :: proc(s: ^Draw_Surface, vertices: ..Vertex) {
	append(&s.vertices, ..vertices)
}

__indices :: proc(s: ^Draw_Surface, indices: ..u16) {
	append(&s.indices, ..indices)
}

/*
	Basic shapes drawn in immediate mode
*/
draw_triangle_fill :: proc(a, b, c: [2]f32, color: Color) {
	surface := __get_draw_surface()
	i := len(surface.vertices)
	__vertices(surface, 
		Vertex{pos = a, col = color},
		Vertex{pos = b, col = color},
		Vertex{pos = c, col = color},
		)
	__indices(surface,
		u16(i),
		u16(i + 1),
		u16(i + 2),
		)
}
draw_triangle_strip_fill :: proc(points: [][2]f32, color: Color) {
	if len(points) < 4 {
		return
	}
	for i in 2 ..< len(points) {
		if i % 2 == 0 {
			draw_triangle_fill(
				{points[i].x, points[i].y},
				{points[i - 2].x, points[i - 2].y},
				{points[i - 1].x, points[i - 1].y},
				color,
			)
		} else {
			draw_triangle_fill(
				{points[i].x, points[i].y},
				{points[i - 1].x, points[i - 1].y},
				{points[i - 2].x, points[i - 2].y},
				color,
			)
		}
	}
}
draw_line :: proc(a, b: [2]f32, thickness: f32, color: Color) {
	delta := b - a
	length := math.sqrt(f32(delta.x * delta.x + delta.y * delta.y))
	if length > 0 && thickness > 0 {
		scale := thickness / (2 * length)
		radius: [2]f32 = {-scale * delta.y, scale * delta.x}
		draw_triangle_strip_fill({
			{ a.x - radius.x, a.y - radius.y },
			{ a.x + radius.x, a.y + radius.y },
			{ b.x - radius.x, b.y - radius.y },
			{ b.x + radius.x, b.y + radius.y },
		}, color)
	}
}

draw_bezier_stroke :: proc(p0, p1, p2, p3: [2]f32, segments: int, thickness: f32, color: Color) {
	step: f32 = 1.0 / f32(segments)
	lp: [2]f32 = p0
	for t: f32 = step; t <= 1; t += step {
		times: matrix[1, 4]f32 = {1, t, t * t, t * t * t}
		weights: matrix[4, 4]f32 = {
			1, 0, 0, 0,
			-3, 3, 0, 0,
			3, -6, 3, 0,
			-1, 3, -3, 1,
		}
		p: [2]f32 = {
			(times * weights * (matrix[4, 1]f32){p0.x, p1.x, p2.x, p3.x})[0][0],
			(times * weights * (matrix[4, 1]f32){p0.y, p1.y, p2.y, p3.y})[0][0],
		}
		draw_line(lp, p, thickness, color)
		lp = p
	}
}

get_arc_steps :: proc(radius, angle: f32) -> int {
	return max(int((angle / (math.PI * 0.1)) * (radius * 0.25)), 4)
}
// Draw a filled arc around a given center
draw_arc_fill :: proc(center: [2]f32, radius, from, to: f32, color: Color) {
	surface := __get_draw_surface()

	from, to := from, to
	if from > to do from, to = to, from
	da := to - from
	nsteps := get_arc_steps(radius, da)

	i := len(surface.vertices)

	__vertices(surface, Vertex{pos = center, col = color})
	for n in 0..=nsteps {
		a := from + da * f32(n) / f32(nsteps)
		j := len(surface.vertices)
		__vertices(surface, 
			Vertex{pos = center + {math.cos(a), math.sin(a)} * radius, col = color},
			)
		if n < nsteps {
			__indices(surface, 
				u16(i), 
				u16(j), 
				u16(j + 1),
				)
		}
	}
}
// Draw a stroke along an arc
draw_arc_stroke :: proc(center: [2]f32, radius, from, to, thickness: f32, color: Color) {
	surface := __get_draw_surface()

	from, to := from, to
	if from > to do from, to = to, from
	da := to - from
	nsteps := get_arc_steps(radius, da)

	i := len(surface.vertices)

	begin_path()
	for n in 0..=nsteps {
		a := from + da * f32(n) / f32(nsteps)
		j := len(surface.vertices)
		point(center + {math.cos(a), math.sin(a)} * radius)
	}
	stroke_path(thickness, color, .Inner)
	end_path()
}
draw_box_fill :: proc(box: Box, color: Color) {
	surface := __get_draw_surface()
	i := len(surface.vertices)
	__vertices(surface, 
		Vertex{pos = box.low, col = color, z = surface.z},
		Vertex{pos = {box.low.x, box.high.y}, col = color, z = surface.z},
		Vertex{pos = box.high, col = color, z = surface.z},
		Vertex{pos = {box.high.x, box.low.y}, col = color, z = surface.z},
		)
	__indices(surface,
		u16(i),
		u16(i + 2),
		u16(i + 1),
		u16(i),
		u16(i + 3),
		u16(i + 2),
		)
}
draw_box_stroke :: proc(box: Box, thickness: f32, color: Color) {
	draw_box_fill({box.low, {box.high.x, box.low.y + thickness}}, color)
	draw_box_fill({{box.low.x, box.high.y - thickness}, box.high}, color)
	draw_box_fill({{box.low.x, box.low.y + thickness}, {box.low.x + thickness, box.high.y - thickness}}, color)
	draw_box_fill({{box.high.x - thickness, box.low.y + thickness}, {box.high.x, box.high.y - thickness}}, color)
}
draw_rounded_box_fill :: proc(box: Box, radius: f32, color: Color) {
	if box.high.x <= box.low.x || box.high.y <= box.low.y {
		return
	}
	radius := min(radius, (box.high.x - box.low.x) / 2, (box.high.y - box.low.y) / 2)
	if radius <= 0 {
		draw_box_fill(box, color)
		return
	}
	draw_arc_fill(box.low + radius, radius, math.PI, math.PI * 1.5, color)
	draw_arc_fill({box.high.x - radius, box.low.y + radius}, radius, math.PI * 1.5, math.PI * 2, color)
	draw_arc_fill(box.high - radius, radius, 0, math.PI * 0.5, color)
	draw_arc_fill({box.low.x + radius, box.high.y - radius}, radius, math.PI * 0.5, math.PI, color)
	if box.high.x - radius > box.low.x + radius {
		draw_box_fill({{box.low.x + radius, box.low.y}, {box.high.x - radius, box.high.y}}, color)
	}
	if box.high.y - radius > box.low.y + radius {
		draw_box_fill({{box.low.x, box.low.y + radius}, {box.low.x + radius, box.high.y - radius}}, color)
		draw_box_fill({{box.high.x - radius, box.low.y + radius}, {box.high.x, box.high.y - radius}}, color)
	}
}

draw_rounded_box_corners_fill :: proc(box: Box, radius: f32, corners: Corners, color: Color) {
	if box.high.x <= box.low.x || box.high.y <= box.low.y {
		return
	}
	radius := min(radius, (box.high.x - box.low.x) / 2, (box.high.y - box.low.y) / 2)
	if radius <= 0 || corners == {} {
		draw_box_fill(box, color)
		return
	}
	if .Top_Left in corners {
		draw_arc_fill(box.low + radius, radius, math.PI, math.PI * 1.5, color)
	} else {
		draw_box_fill({box.low, box.low + radius}, color)
	}
	if .Top_Right in corners {
		draw_arc_fill({box.high.x - radius, box.low.y + radius}, radius, math.PI * 1.5, math.PI * 2, color)
	} else {
		draw_box_fill({{box.high.x - radius, box.low.y}, {box.high.x, box.low.y + radius}}, color)
	}
	if .Bottom_Right in corners {
		draw_arc_fill(box.high - radius, radius, 0, math.PI * 0.5, color)
	} else {
		draw_box_fill({box.high - radius, box.high}, color)
	}
	if .Bottom_Left in corners {
		draw_arc_fill({box.low.x + radius, box.high.y - radius}, radius, math.PI * 0.5, math.PI, color)
	} else {
		draw_box_fill({{box.low.x, box.high.y - radius}, {box.low.x + radius, box.high.y}}, color)
	}
	if box.high.x - radius > box.low.x + radius {
		draw_box_fill({{box.low.x + radius, box.low.y}, {box.high.x - radius, box.high.y}}, color)
	}
	if box.high.y - radius > box.low.y + radius {
		draw_box_fill({{box.low.x, box.low.y + radius}, {box.low.x + radius, box.high.y - radius}}, color)
		draw_box_fill({{box.high.x - radius, box.low.y + radius}, {box.high.x, box.high.y - radius}}, color)
	}
}

draw_rounded_box_stroke :: proc(box: Box, radius, thickness: f32, color: Color) {
	if box.high.x <= box.low.x || box.high.y <= box.low.y {
		return
	}
	radius := min(radius, (box.high.x - box.low.x) / 2, (box.high.y - box.low.y) / 2)
	if radius <= 0 {
		draw_box_stroke(box, thickness, color)
		return
	}
	draw_arc_stroke(box.low + radius, radius, math.PI, math.PI * 1.5, thickness, color)
	draw_arc_stroke({box.high.x - radius, box.low.y + radius}, radius, math.PI * 1.5, math.PI * 2, thickness, color)
	draw_arc_stroke(box.high - radius, radius, 0, math.PI * 0.5, thickness, color)
	draw_arc_stroke({box.low.x + radius, box.high.y - radius}, radius, math.PI * 0.5, math.PI, thickness, color)
	if box.high.x - radius > box.low.x + radius {
		draw_box_fill({{box.low.x + radius, box.low.y}, {box.high.x - radius, box.low.y + thickness}}, color)
		draw_box_fill({{box.low.x + radius, box.high.y - thickness}, {box.high.x - radius, box.high.y}}, color)
	}
	if box.high.y - radius > box.low.y + radius {
		draw_box_fill({{box.low.x, box.low.y + radius}, {box.low.x + thickness, box.high.y - radius}}, color)
		draw_box_fill({{box.high.x - thickness, box.low.y + radius}, {box.high.x, box.high.y - radius}}, color)
	}
}

draw_texture :: proc(source, target: Box, color: Color) {
	surface := __get_draw_surface()
	i := len(surface.vertices)
	tex_size: [2]f32 = {f32(core.atlas.width), f32(core.atlas.height)}
	__vertices(surface, 
		Vertex{
			pos = target.low, 
			col = color, 
			uv = source.low / tex_size,
			z = surface.z,
		},
		Vertex{
			pos = {target.low.x, target.high.y}, 
			col = color, 
			uv = [2]f32{source.low.x, source.high.y} / tex_size,
			z = surface.z,
		},
		Vertex{
			pos = target.high, 
			col = color, 
			uv = source.high / tex_size,
			z = surface.z,
		},
		Vertex{
			pos = {target.high.x, target.low.y}, 
			col = color, 
			uv = [2]f32{source.high.x, source.low.y} / tex_size,
			z = surface.z,
		},
		)
	__indices(surface,
		u16(i),
		u16(i + 2),
		u16(i + 1),
		u16(i),
		u16(i + 3),
		u16(i + 2),
		)
}

foreground :: proc() {
	layout := current_layout()
	draw_rounded_box_fill(layout.box, core.style.rounding, core.style.color.foreground)
	draw_rounded_box_stroke(layout.box, core.style.rounding, 1, core.style.color.substance)
}*/
