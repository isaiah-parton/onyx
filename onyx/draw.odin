package onyx

import "core:fmt"
import "core:math"
import "core:math/linalg"

import sg "extra:sokol-odin/sokol/gfx"

ANGLE_TOLERANCE :: 0.1
MAX_PATH_POINTS :: 400
MAX_MATRICES :: 100
MAX_DRAW_CALLS :: 50
MAX_DRAW_CALL_TEXTURES :: 8
MAX_FONTS :: 100
MAX_ATLASES :: 8
MAX_IMAGES :: 256
MIN_ATLAS_SIZE :: 1024
MAX_ATLAS_SIZE :: 4096

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

Vertex :: struct {
	pos: [3]f32,
	uv: [2]f32,
	col: [4]u8,
}

Vertex_State :: struct {
	uv: [2]f32,
	col: [4]u8,
	z: f32,
}

// Matrix used for vertex transforms
Matrix :: matrix[4, 4]f32

// A draw call to the GPU these are managed internally
Draw_Call :: struct {
	gradient: Gradient,
	scissor_box: Maybe(Box),

	bindings: sg.Bindings,

	vertices: [dynamic]Vertex,
	indices: [dynamic]u16,

	ready: bool,
}

Path :: struct {
	points: [MAX_PATH_POINTS][2]f32,
	count: int,
	closed: bool,
}

vertex_uv :: proc(uv: [2]f32) {
	core.vertex_state.uv = uv
}

vertex_col :: proc(color: Color) {
	core.vertex_state.col = color
}

// Append a vertex and return it's index
add_vertex_3f32 :: proc(x, y, z: f32) -> (i: u16) {
	pos: [3]f32 = {
		core.current_matrix[0, 0] * x + core.current_matrix[0, 1] * y + core.current_matrix[0, 2] * z + core.current_matrix[0, 3],
		core.current_matrix[1, 0] * x + core.current_matrix[1, 1] * y + core.current_matrix[1, 2] * z + core.current_matrix[1, 3],
		core.current_matrix[2, 0] * x + core.current_matrix[2, 1] * y + core.current_matrix[2, 2] * z + core.current_matrix[2, 3],
	}
	i = u16(len(core.current_draw_call.vertices))
	append(&core.current_draw_call.vertices, Vertex{
		pos = pos,
		uv = core.vertex_state.uv,
		col = core.vertex_state.col,
	})
	return
}

add_vertex_2f32 :: proc(x, y: f32) -> u16 {
	return add_vertex_3f32(x, y, core.vertex_state.z)
}

add_vertex_point :: proc(point: [2]f32) -> u16 {
	return add_vertex_2f32(point.x, point.y)
}

add_vertex :: proc {
	add_vertex_3f32,
	add_vertex_2f32,
	add_vertex_point,
}

add_index :: proc(i: u16) {
	append(&core.current_draw_call.indices, i)
}

add_indices :: proc(i: ..u16) {
	append(&core.current_draw_call.indices, ..i)
}

push_matrix :: proc() {
	push_stack(&core.matrix_stack, matrix_identity())
	core.current_matrix = &core.matrix_stack.items[core.matrix_stack.height - 1]
}

pop_matrix :: proc() {
	assert(core.matrix_stack.height > 0)
	pop_stack(&core.matrix_stack)
	core.current_matrix = &core.matrix_stack.items[max(0, core.matrix_stack.height - 1)]
}

push_draw_call :: proc() {
	core.current_draw_call = &core.draw_calls[core.draw_call_count]
	if !core.current_draw_call.ready {
		core.current_draw_call.bindings.index_buffer = sg.make_buffer(sg.Buffer_Desc{
			type = .INDEXBUFFER,
			usage = .STREAM,
			size = MAX_DRAW_CALL_INDICES * size_of(u16),
		})
		core.current_draw_call.bindings.vertex_buffers[0] = sg.make_buffer(sg.Buffer_Desc{
			type = .VERTEXBUFFER,
			usage = .STREAM,
			size = MAX_DRAW_CALL_VERTICES * size_of(Vertex),
		})
		core.current_draw_call.bindings.fs.samplers[0] = sg.make_sampler(sg.Sampler_Desc{
			min_filter = .LINEAR,
			mag_filter = .LINEAR,
			wrap_u = .MIRRORED_REPEAT,
			wrap_v = .MIRRORED_REPEAT,
		})
		reserve(&core.current_draw_call.vertices, MAX_DRAW_CALL_VERTICES)
		reserve(&core.current_draw_call.indices, MAX_DRAW_CALL_INDICES)
		core.current_draw_call.ready = true
	}
	core.draw_call_count += 1
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
	core.current_matrix^ *= linalg.matrix4_translate([3]f32{x, y, z})
}

rotate_matrix :: proc(angle, x, y, z: f32) {
	core.current_matrix^ *= linalg.matrix4_rotate(angle, [3]f32{x, y, z})
}

rotate_matrix_z :: proc(angle: f32) {
	cosres := math.cos(angle)
	sinres := math.sin(angle)

	rotation_matrix: Matrix = {
		cosres, 	-sinres, 	0, 0,
		sinres, 	cosres, 	0, 0,
		0, 				0, 				1, 0,
		0, 				0, 				0, 1,
	}

	core.current_matrix^ *= rotation_matrix
}

scale_matrix :: proc(x, y, z: f32) {
	core.current_matrix^ *= linalg.matrix4_scale([3]f32{x, y, z})
}