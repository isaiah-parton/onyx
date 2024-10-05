package onyx

import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:mem"

import "vendor:wgpu"

// ANGLE_TOLERANCE :: 0.1
MAX_PATH_POINTS :: 400
MAX_MATRICES :: 100
MAX_DRAW_CALLS :: 64

MAX_FONTS :: 100
// MAX_IMAGES :: 256

MAX_ATLASES :: 8
MIN_ATLAS_SIZE :: 1024
MAX_ATLAS_SIZE :: 8192

BUFFER_SIZE :: mem.Megabyte * 2
MAX_VERTICES :: 65536
MAX_INDICES :: 65536

PRIMITIVE_BUFFER_CAP :: size_of(Primitive) * 1024
PAINT_BUFFER_CAP :: size_of(Paint) * 1024

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
	Image,
	Linear_Gradient,
	Radial_Gradient,
}

Paint :: struct {
	kind: Paint_Kind,
	col0: [4]f32,
	col1: [4]f32,
}

Primitive_Kind :: enum u32 {
	Normal,
	Circle,
	Rect,
}

Primitive :: struct {
	kind:   Primitive_Kind,
	cv0:    [2]f32,
	cv1:    [2]f32,
	cv2:    [2]f32,
	radius: f32,
	image:  u32,
	paint:  u32,
}

Vertex :: struct {
	pos:  [2]f32,
	uv:   [2]f32,
	col:  [4]u8,
	prim: u32,
}

Vertex_State :: struct {
	uv:    [2]f32,
	col:   [4]u8,
	prim:  u32,
	alpha: f32,
}

// Matrix used for vertex transforms
Matrix :: matrix[4, 4]f32

Draw_List :: struct {
	vertices: [dynamic]Vertex,
	indices:  [dynamic]u32,
	prims:    [dynamic]Primitive,
	paints:   [dynamic]Paint,
}

// A draw call to the GPU these are managed internally
Draw_Call :: struct {
	gradient:                Gradient,
	clip_box:                Box,
	texture:                 wgpu.Texture,
	elem_offset, elem_count: int,
	index:                   int,
}

Path :: struct {
	points: [MAX_PATH_POINTS][2]f32,
	count:  int,
	closed: bool,
}

init_draw_list :: proc(draw_list: ^Draw_List) {
	reserve(&draw_list.vertices, MAX_VERTICES)
	reserve(&draw_list.indices, MAX_INDICES)
}

destroy_draw_list :: proc(draw_list: ^Draw_List) {
	delete(draw_list.vertices)
	delete(draw_list.indices)
}

clear_draw_list :: proc(draw_list: ^Draw_List) {
	clear(&draw_list.vertices)
	clear(&draw_list.indices)
	clear(&draw_list.prims)
}

add_circle_primitive :: proc(center: [2]f32, radius: f32) -> u32 {
	index := u32(len(core.draw_list.prims))
	append(&core.draw_list.prims, Primitive{kind = .Circle, cv0 = center, radius = radius})
	return index
}

set_vertex_prim :: proc(prim: u32) {
	core.vertex_state.prim = prim
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
	pos: [2]f32 = {
		core.current_matrix[0, 0] * x +
		core.current_matrix[0, 1] * y +
		core.current_matrix[0, 2] +
		core.current_matrix[0, 3],
		core.current_matrix[1, 0] * x +
		core.current_matrix[1, 1] * y +
		core.current_matrix[1, 2] +
		core.current_matrix[1, 3],
	}
	i = next_vertex_index()
	append(
		&core.draw_list.vertices,
		Vertex {
			pos = pos,
			uv = core.vertex_state.uv,
			col = core.vertex_state.col,
			prim = core.vertex_state.prim,
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
	append(&core.draw_list.indices, i)
	core.current_draw_call.elem_count += 1
}

add_indices :: proc(i: ..u32) {
	assert(core.current_draw_call != nil)
	append(&core.draw_list.indices, ..i)
	core.current_draw_call.elem_count += len(i)
}

next_vertex_index :: proc() -> u32 {
	return u32(len(core.draw_list.vertices))
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

append_draw_call :: proc(index: int, loc := #caller_location) {
	assert(core.draw_call_count < MAX_DRAW_CALLS, "outa draw calls dawg", loc)
	core.current_draw_call = &core.draw_calls[core.draw_call_count]
	core.current_draw_call^ = Draw_Call {
		elem_offset = len(core.draw_list.indices),
		index       = index,
		clip_box    = current_clip().? or_else view_box(),
		texture     = core.current_texture,
	}
	core.draw_call_count += 1
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
