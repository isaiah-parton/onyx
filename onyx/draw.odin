package onyx

import "core:fmt"
import "core:math"
import "core:math/linalg"

import sg "extra:sokol-odin/sokol/gfx"

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
	tex: i32,
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

set_vertex_color :: proc(color: Color) {
	core.vertex_color = color
}

set_vertex_uv :: proc(uv: [2]f32) {
	core.vertex_uv = uv
}

// Append a vertex and return it's index
add_vertex_3f32 :: proc(x, y, z: f32) -> int {
	pos: [3]f32 = {
		core.current_matrix[0, 0] * x + core.current_matrix[0, 1] * y + core.current_matrix[0, 2] * z + core.current_matrix[0, 3],
		core.current_matrix[1, 0] * x + core.current_matrix[1, 1] * y + core.current_matrix[1, 2] * z + core.current_matrix[1, 3],
		core.current_matrix[2, 0] * x + core.current_matrix[2, 1] * y + core.current_matrix[2, 2] * z + core.current_matrix[2, 3],
	}

	return append(&core.current_draw_call.vertices, Vertex{
		pos = pos,
		uv = core.vertex_uv,
		col = core.vertex_color,
	})
}

add_vertex_2f32 :: proc(x, y: f32) -> int {
	return add_vertex_3f32(ctx, x, y, core.vertex_z)
}

add_vertex :: proc {
	add_vertex_3f32,
	add_vertex_2f32,
}

push_matrix :: proc() {
	push(&core.matrix_stack, matrix_identity())
	core.current_matrix = &core.matrix_stack.items[core.matrix_stack.height - 1]
}

pop_matrix :: proc() {
	stack.pop(&core.matrix_stack)
	assert(core.matrix_stack.height >= 1)
	core.current_matrix = &core.matrix_stack.items[core.matrix_stack.height - 1]
}

push_draw_call :: proc() {
	push(&core.draw_call_stack, Draw_Call{})
	core.current_draw_call = &core.draw_call_stack.items[core.draw_call_stack.height - 1]
}

matrix_identity :: proc() -> Matrix {
	return {
		1, 0, 0, 0,
		0, 1, 0, 0,
		0, 0, 1, 0,
		0, 0, 0, 1,
	}
}

translate_matrix :: proc(x, y, z: f32) {
	translation_matrix: Matrix = {
		1, 0, 0, x,
	    0, 1, 0, y,
	    0, 0, 1, z,
	    0, 0, 0, 1,
	}

	core.current_matrix^ *= translation_matrix
}

rotate_matrix :: proc(angle, x, y, z: f32) {
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

	core.current_matrix^ *= rotation_matrix
}

scale_matrix :: proc(x, y, z: f32) {
	scale_matrix: matrix[4, 4]f32 = {
		x, 0, 0, 0,
		0, y, 0, 0,
		0, 0, z, 0,
		0, 0, 0, 1,
	}

	core.current_matrix^ *= scale_matrix
}