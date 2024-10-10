package onyx

import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:mem"

import "vendor:wgpu"

MAX_PATH_POINTS :: 400
MAX_MATRICES :: 100
MAX_DRAW_CALLS :: 64

MAX_FONTS :: 100

MAX_ATLASES :: 8
MIN_ATLAS_SIZE :: 1024
MAX_ATLAS_SIZE :: 8192

BUFFER_SIZE :: mem.Megabyte * 2

Gradient :: union {
	Linear_Gradient,
	Radial_Gradient,
}

Linear_Gradient :: struct {
	points: [2][2]f32,
	colors: [2]Color,
}

Radial_Gradient :: struct {
	center: [2]f32,
	radius: f32,
	colors: [2]Color,
}

Stroke_Justify :: enum {
	Inner,
	Center,
	Outer,
}

Paint_Kind :: enum u32 {
	Normal,
	Glyph,
	User_Image,
	Linear_Gradient,
	Radial_Gradient,
}

Paint :: struct #align (16) {
	kind:    Paint_Kind,
	padding: [3]u32,
	col0:    [4]f32,
	col1:    [4]f32,
	size:    f32,
	image:   u32,
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

Shape :: struct #align (16) {
	kind:    Shape_Kind,
	padding: u32,
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

Vertex :: struct {
	pos:   [2]f32,
	uv:    [2]f32,
	col:   [4]u8,
	shape: u32,
}

Vertex_State :: struct {
	uv:      [2]f32,
	col:     [4]u8,
	shape:   u32,
	alpha:   f32,
	padding: u64,
}

// Matrix used for vertex transforms
Matrix :: matrix[4, 4]f32

Draw_Call :: struct {
	user_texture: Maybe(wgpu.Texture),
	elem_offset:  int,
	elem_count:   int,
	index:        int,
}

Path :: struct {
	points: [MAX_PATH_POINTS][2]f32,
	count:  int,
	closed: bool,
}

Draw_State :: struct {
	scissor: u32,
	paint:   u32,
	shape:   u32,
	xform:   u32,
}

set_scissor_shape :: proc(shape: u32) {
	core.draw_state.scissor = shape
}

set_paint :: proc(paint: u32) {
	core.draw_state.paint = paint
}

add_paint :: proc(paint: Paint) -> u32 {
	index := u32(len(core.gfx.paints.data))
	append(&core.gfx.paints.data, paint)
	return index
}

set_vertex_shape :: proc(shape: u32) {
	core.vertex_state.shape = shape
}

set_vertex_uv :: proc(uv: [2]f32) {
	core.vertex_state.uv = uv
}

set_vertex_color :: proc(color: Color) {
	if core.vertex_state.alpha == 1 {
		core.vertex_state.col = color
		return
	}
	core.vertex_state.col = {
		color.r,
		color.g,
		color.b,
		u8((f32(color.a) / 255) * core.vertex_state.alpha * 255),
	}
}

set_global_alpha :: proc(alpha: f32) {
	core.vertex_state.alpha = alpha
}

// Append a vertex and return it's index
add_vertex_2f32 :: proc(x, y: f32) -> (i: u32) {
	i = next_vertex_index()
	append(
		&core.gfx.vertices,
		Vertex {
			pos = {x, y},
			uv = core.vertex_state.uv,
			col = core.vertex_state.col,
			shape = core.vertex_state.shape,
		},
	)
	return
}

add_vertex_point :: proc(point: [2]f32) -> u32 {
	return add_vertex_2f32(point.x, point.y)
}

add_vertex :: proc {
	add_vertex_2f32,
	add_vertex_point,
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
	assert(core.matrix_stack.height > 0)
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

// Add a new draw call at the given index with the currently bound user texture
append_draw_call :: proc(index: int, loc := #caller_location) {
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
