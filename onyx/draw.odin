package onyx

import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:mem"
import "core:reflect"

import "vendor:wgpu"

MAX_PATH_POINTS :: 400
MAX_MATRICES :: 100
MAX_DRAW_CALLS :: 64

MAX_FONTS :: 100

MAX_ATLASES :: 8
MIN_ATLAS_SIZE :: 1024
MAX_ATLAS_SIZE :: 8192

BUFFER_SIZE :: mem.Megabyte * 2

// Glyph_Paint :: struct {}

// Atlas_Paint :: struct {
// 	alpha_correction: f32,
// }

// User_Texture_Paint :: struct {
// 	texture: wgpu.Texture,
// }

// Linear_Gradient :: struct {
// 	points: [2][2]f32,
// 	colors: [2]Color,
// }

// Radial_Gradient :: struct {
// 	center: [2]f32,
// 	radius: f32,
// 	colors: [2]Color,
// }

// Simplex_Noise_Gradient :: struct {
// 	colors: [2]Color,
// }

// Paint option passed to draw procedures
// Shape_Paint :: union #no_nil {
// 	Color,
// 	Glyph_Paint,
// 	User_Texture_Paint,
// 	Linear_Gradient,
// 	Radial_Gradient,
// 	Simplex_Noise_Gradient,
// }

Paint_Kind :: enum u32 {
	Normal,
	Glyph,
	User_Image,
	Skeleton,
	Linear_Gradient,
	Radial_Gradient,
}

Stroke_Justify :: enum {
	Inner,
	Center,
	Outer,
}

Shape_Kind :: enum u32 {
	Normal,
	Circle,
	Box,
	BlurredBox,
	Arc,
	Bezier,
	Pie,
	Path,
	Polygon,
}

// `Paint` and `Shape` get sent to the GPU

Paint :: struct #align (8) {
	kind: Paint_Kind,
	pad0: [1]u32,
	cv0:  [2]f32,
	cv1:  [2]f32,
	pad1: [2]u32,
	col0: [4]f32,
	col1: [4]f32,
}

Shape :: struct #align (16) {
	kind:    Shape_Kind,
	pad0:    u32,
	cv0:     [2]f32,
	cv1:     [2]f32,
	cv2:     [2]f32,
	corners: [4]f32,
	radius:  f32,
	width:   f32,
	paint:   u32,
	scissor: u32,
	start:   u32,
	count:   u32,
	stroke:  b32,
	xform:   u32,
}

Matrix :: matrix[4, 4]f32

Vertex :: struct {
	pos:   [2]f32,
	uv:    [2]f32,
	col:   [4]u8,
	shape: u32,
}

Draw_Call :: struct {
	user_texture:      Maybe(wgpu.Texture),
	user_sampler_desc: Maybe(wgpu.SamplerDescriptor),
	elem_offset:       int,
	elem_count:        int,
	index:             int,
}

Path :: struct {
	points: [MAX_PATH_POINTS][2]f32,
	count:  int,
	closed: bool,
}

Draw_State :: struct {
	scissor:    u32,
	paint:      u32,
	shape:      u32,
	xform:      u32,
	path_start: u32,
	path_point: [2]f32,
}

// The current scissor state has a box for mathematical clipping done by the CPU
// and an optional shape for fragment shader clipping
// The effect of scissor shapes currently do not stack in the shader
Scissor :: struct {
	box:   Box,
	shape: u32,
}

push_scissor :: proc(box: Box, shape: u32 = 0) {
	box := box
	if scissor, ok := current_scissor().?; ok {
		box = clamp_box(box, scissor.box)
	}
	push_stack(&core.scissor_stack, Scissor{box = box, shape = shape})
	set_scissor_shape(shape)
}

pop_scissor :: proc() {
	pop_stack(&core.scissor_stack)
	if scissor, ok := current_scissor().?; ok {
		set_scissor_shape(scissor.shape)
	}
}

current_scissor :: proc() -> Maybe(Scissor) {
	if core.scissor_stack.height > 0 {
		return core.scissor_stack.items[core.scissor_stack.height - 1]
	}
	return nil
}

set_scissor_shape :: proc(shape: u32) {
	core.draw_state.scissor = shape
}

add_paint_linear_gradient :: proc(p0, p1: [2]f32, col0, col1: [4]u8) -> u32 {
	return add_paint(
		{
			kind = .Linear_Gradient,
			cv0 = p0,
			cv1 = p1,
			col0 = normalize_color(col0),
			col1 = normalize_color(col1),
		},
	)
}

set_paint :: proc(paint: u32) {
	core.draw_state.paint = paint
}

path_begin :: proc() {
	core.draw_state.path_start = u32(len(core.gfx.cvs.data))
}
path_move_to :: proc(p: [2]f32) {
	core.draw_state.path_point = p
}
path_quad_to :: proc(cp, p: [2]f32) {
	append(&core.gfx.cvs.data, core.draw_state.path_point, cp, p)
	path_move_to(p)
}
path_line_to :: proc(p: [2]f32) {
	path_quad_to(linalg.lerp(core.draw_state.path_point, p, 0.5), p)
}
path_fill :: proc() {
	vertex_count := u32(len(core.gfx.cvs.data)) - core.draw_state.path_start
	render_shape(
		add_shape(
			Shape{kind = .Path, start = core.draw_state.path_start, count = vertex_count / 3},
		),
		255,
	)
}

// Add a paint to the the shader buffer and return its index
add_paint :: proc(paint: Paint) -> u32 {
	index := u32(len(core.gfx.paints.data))
	append(&core.gfx.paints.data, paint)
	return index
}

add_xform :: proc(xform: Matrix) -> u32 {
	index := u32(len(core.gfx.xforms.data))
	append(&core.gfx.xforms.data, xform)
	return index
}

set_shape :: proc(shape: u32) {
	core.draw_state.shape = shape
}

// Append a vertex and return it's index
add_vertex :: proc(v: Vertex) -> u32 {
	index := u32(len(core.gfx.vertices))
	append(&core.gfx.vertices, v)
	return index
}

add_index :: proc(i: u32) {
	assert(core.current_draw_call != nil)
	append(&core.gfx.indices, i)
	core.current_draw_call.elem_count += 1
}

add_indices :: proc(i: ..u32) {
	assert(core.current_draw_call != nil)
	append(&core.gfx.indices, ..i)
	core.current_draw_call.elem_count += len(i)
}

next_vertex_index :: proc() -> u32 {
	return u32(len(core.gfx.vertices))
}

current_matrix :: proc() -> Maybe(Matrix) {
	if core.matrix_stack.height > 0 {
		return core.matrix_stack.items[core.matrix_stack.height - 1]
	}
	return nil
}

push_matrix :: proc() {
	push_stack(&core.matrix_stack, current_matrix().? or_else matrix_identity())
	core.current_matrix = &core.matrix_stack.items[core.matrix_stack.height - 1]
}

pop_matrix :: proc() {
	pop_stack(&core.matrix_stack)
	core.current_matrix = &core.matrix_stack.items[max(0, core.matrix_stack.height - 1)]
}

matrix_identity :: proc() -> Matrix {
	return {1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1}
}

translate_matrix :: proc(x, y, z: f32) {
	core.current_matrix^ *= linalg.matrix4_translate([3]f32{x, y, z})
}

rotate_matrix :: proc(angle, x, y, z: f32) {
	core.current_matrix^ *= linalg.matrix4_rotate(angle, [3]f32{x, y, z})
}

rotate_matrix_z :: proc(angle: f32) {
	cosres := math.cos(angle)
	sinres := math.sin(angle)
	rotation_matrix: Matrix = {cosres, -sinres, 0, 0, sinres, cosres, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1}
	core.current_matrix^ *= rotation_matrix
}

scale_matrix :: proc(x, y, z: f32) {
	core.current_matrix^ *= linalg.matrix4_scale([3]f32{x, y, z})
}

// Lets the user provide a custom sampler descriptor for the user texture
set_sampler_descriptor :: proc(desc: wgpu.SamplerDescriptor) {
	if core.current_draw_call == nil do return
	if core.current_draw_call.user_sampler_desc != nil {
		append_draw_call(current_layer().?.index)
	}
	core.current_draw_call.user_sampler_desc = desc
}

// Set the texture to be used for `draw_texture()`
set_texture :: proc(texture: wgpu.Texture) {
	core.current_texture = texture
	if core.current_draw_call == nil do return
	if core.current_draw_call.user_texture == core.current_texture do return
	if core.current_draw_call.user_texture != nil {
		append_draw_call(current_layer().?.index)
	}
	core.current_draw_call.user_texture = texture
}

// Returns the current user texture
get_current_texture :: proc() -> wgpu.Texture {
	return core.current_texture
}

// Add a new draw call at the given index with the currently bound user texture
append_draw_call :: proc(index: int) {
	append(
		&core.draw_calls,
		Draw_Call {
			index = index,
			elem_offset = len(core.gfx.indices),
			user_texture = core.current_texture,
		},
	)
	core.current_draw_call = &core.draw_calls[len(core.draw_calls) - 1]
}
