package vgo
// Time to work out the intended usage of this renderer
//
// Index of a paint that was already added
// this exists so paints can be reused
// 		Paint_Handle :: distinct int
//
// We could add an optional paint argument to all draw procedures
// 		fill_box(..., Solid_Color(BROWN))
//
// If none is provided, the paint in `core.draw_state` will be used
// 		set_paint(linear_gradient({100, 200}, {520, 340}, RED, MAROON))
// 		stroke_box(...)
// 		fill_circle(...)
//
// Or pass a `Paint_Handle`
// 		paint0 := add_paint(GRAY(0.5))
// 		paint1 := add_paint(GRAY(0.8))
// 		fill_box(..., paint0)
// 		fill_box(..., paint1)
// 		stroke_box(..., paint0)
// 		stroke_box(..., paint1)
//
//
//
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

BUFFER_SIZE :: mem.Megabyte

Matrix :: matrix[4, 4]f32

Paint_Kind :: enum u32 {
	// Raw vertex colors
	None,
	// Reserved
	Solid_Color,
	// Sample from the font atlas
	Atlas_Sample,
	// Sample from the user texture
	User_Texture_Sample,
	// A simplex noise shader for ui skeletons
	Skeleton,
	// Do I really have to explain?
	Linear_Gradient,
	Radial_Gradient,
}

Stroke_Justify :: enum {
	// TODO: define inner and outer
	Inner,
	Center,
	Outer,
}

// The paint data sent to the GPU
Paint :: struct #align (8) {
	kind: Paint_Kind,
	pad0: [1]u32,
	cv0:  [2]f32,
	cv1:  [2]f32,
	pad1: [2]u32,
	col0: [4]f32,
	col1: [4]f32,
}

Color :: [4]u8

Paint_Option :: union {
	u32,
	Paint,
	Color,
}

Index :: u16

// I keep UV and color in here purely for the HSVA color wheel, they shouldn't be necessary
Vertex :: struct {
	pos:   [2]f32,
	uv:    [2]f32,
	col:   [4]u8,
	shape: u32,
	paint: u32,
}

// A call to the GPU to draw some stuff
Draw_Call :: struct {
	user_texture:      Maybe(wgpu.Texture),
	user_sampler_desc: Maybe(wgpu.SamplerDescriptor),
	elem_offset:       int,
	elem_count:        int,
	index:             int,
}

Scissor :: struct {
	box:   Box,
	shape: u32,
}

@(test)
test_gpu_structs :: proc() {
	assert(reflect.struct_field_by_name(Paint, "kind").offset == 0)
	assert(reflect.struct_field_by_name(Paint, "cv0").offset == 8)
	assert(reflect.struct_field_by_name(Paint, "cv1").offset == 16)
	assert(reflect.struct_field_by_name(Paint, "col0").offset == 32)
	assert(reflect.struct_field_by_name(Paint, "col1").offset == 48)

	assert(reflect.struct_field_by_name(Paint, "kind").offset == 0)
	assert(reflect.struct_field_by_name(Paint, "next").offset == 4)
	assert(reflect.struct_field_by_name(Paint, "cv0").offset == 8)
	assert(reflect.struct_field_by_name(Paint, "cv1").offset == 16)
	assert(reflect.struct_field_by_name(Paint, "cv2").offset == 24)
	assert(reflect.struct_field_by_name(Paint, "corners").offset == 32)
	assert(reflect.struct_field_by_name(Paint, "radius").offset == 48)
	assert(reflect.struct_field_by_name(Paint, "width").offset == 52)
	assert(reflect.struct_field_by_name(Paint, "start").offset == 56)
	assert(reflect.struct_field_by_name(Paint, "count").offset == 60)
	assert(reflect.struct_field_by_name(Paint, "stroke").offset == 64)
	assert(reflect.struct_field_by_name(Paint, "xform").offset == 68)
	assert(reflect.struct_field_by_name(Paint, "mode").offset == 72)
}

// Push a scissor shape to the stack, the SDF effect stacks.
// If no shape is provided, only shape vertices will be clipped in `box`
push_scissor :: proc(box: Box, shape: u32 = 0) {
	box := box
	if scissor, ok := current_scissor().?; ok {
		box = clamp_box(box, scissor.box)
		if scissor.shape != 0 {
			core.renderer.shapes.data[shape].next = scissor.shape
		}
	}
	core.renderer.shapes.data[shape].mode = .Intersection
	push_stack(&core.scissor_stack, Scissor{box = box, shape = shape})
}

// Pop the last scissor off the stack
pop_scissor :: proc() {
	pop_stack(&core.scissor_stack)
}

// Get the scissor at the top of the stack
current_scissor :: proc() -> Maybe(Scissor) {
	if core.scissor_stack.height > 0 {
		return core.scissor_stack.items[core.scissor_stack.height - 1]
	}
	return nil
}

// Construct a linear gradient paint for the GPU
make_linear_gradient :: proc(start_point, end_point: [2]f32, start_color, end_color: Color) -> Paint {
	return Paint{
		kind = .Linear_Gradient,
		cv0 = start_point,
		cv1 = end_point,
		col0 = normalize_color(start_color),
		col1 = normalize_color(end_color),
	}
}

// Construct a radial gradient paint for the GPU
make_radial_gradient :: proc(center: [2]f32, radius: f32, inner, outer: Color) -> Paint {
	return Paint{
		kind = .Radial_Gradient,
		cv0 = center,
		cv1 = {radius, 0},
		col0 = normalize_color(inner),
		col1 = normalize_color(outer),
	}
}

// Add a paint to the the shader buffer and return its index
add_paint :: proc(paint: Paint) -> u32 {
	index := u32(len(core.renderer.paints.data))
	append(&core.renderer.paints.data, paint)
	return index
}

// This paint will be used by all paints added after the call
set_paint :: proc(paint: u32) {
	core.paint = paint
}

// Path operations
path_begin :: proc() {
	core.path_start = u32(len(core.renderer.cvs.data))
}

path_move_to :: proc(p: [2]f32) {
	core.path_point = p
}

path_quad_to :: proc(cp, p: [2]f32) {
	append(&core.renderer.cvs.data, core.path_point, cp, p)
	path_move_to(p)
}

path_line_to :: proc(p: [2]f32) {
	path_quad_to(linalg.lerp(core.path_point, p, 0.5), p)
}

fill_path :: proc(color: Color) {
	draw_shape(
		add_fill_path(),
		color,
	)
}

add_fill_path :: proc() -> u32 {
	vertex_count := u32(len(core.renderer.cvs.data)) - core.path_start
	return add_shape(
		Shape{kind = .Path, start = core.path_start, count = vertex_count / 3},
	)
}

add_xform :: proc(xform: Matrix) -> u32 {
	index := u32(len(core.renderer.xforms.data))
	append(&core.renderer.xforms.data, xform)
	return index
}

set_shape :: proc(shape: u32) {
	core.draw_state.shape = shape
}

// Append a vertex and return it's index
add_vertex :: proc(v: Vertex) -> u32 {
	index := u32(len(core.renderer.vertices))
	append(&core.renderer.vertices, v)
	return index
}

add_index :: proc(i: u32) {
	assert(core.current_draw_call != nil)
	append(&core.renderer.indices, i)
	core.current_draw_call.elem_count += 1
}

add_indices :: proc(i: ..u32) {
	assert(core.current_draw_call != nil)
	append(&core.renderer.indices, ..i)
	core.current_draw_call.elem_count += len(i)
}

next_vertex_index :: proc() -> u32 {
	return u32(len(core.renderer.vertices))
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
		append_draw_call()
	}
	core.current_draw_call.user_texture = texture
}

@(private)
append_draw_call :: proc() {
	append(
		&core.draw_calls,
		Draw_Call {
			index = core.draw_call_index,
			elem_offset = len(core.renderer.indices),
			user_texture = core.current_texture,
		},
	)
	core.current_draw_call = &core.draw_calls[len(core.draw_calls) - 1]
}
