package vgo

import "core:time"
import "vendor:wgpu"

@(private)
core: Core

@(private)
Core :: struct {
	renderer:          Renderer,
	// Transform matrices
	matrix_stack:      Stack(Matrix, 128),
	current_matrix:    ^Matrix,
	last_matrix:       Matrix,
	matrix_index:      u32,
	// Scissors are capped at 8 for the sake of sanity
	scissor_stack:     Stack(Scissor, 8),
	draw_calls:        [dynamic]Draw_Call,
	draw_call_index:   int,
	current_draw_call: ^Draw_Call,
	current_texture:   wgpu.Texture,
	paint:             u32,
	shape:             u32,
	xform:             u32,
	path_start:        u32,
	path_point:        [2]f32,
	start_time:        time.Time,
}

// Call before using vgo
start :: proc() {
	core.start_time = time.now()
}

// Call when you're done using vgo
done :: proc() {
	delete(core.draw_calls)
}

Stack :: struct($T: typeid, $N: int) {
	items:  [N]T,
	height: int,
}

push_stack :: proc(stack: ^Stack($T, $N), item: T) -> bool {
	if stack.height < 0 || stack.height >= N {
		return false
	}
	stack.items[stack.height] = item
	stack.height += 1
	return true
}

pop_stack :: proc(stack: ^Stack($T, $N)) {
	stack.height -= 1
}

inject_stack :: proc(stack: ^Stack($T, $N), at: int, item: T) -> bool {
	if at == stack.height {
		return push_stack(stack, item)
	}
	copy(stack.items[at + 1:], stack.items[at:])
	stack.items[at] = item
	stack.height += 1
	return true
}

clear_stack :: proc(stack: ^Stack($T, $N)) {
	stack.height = 0
}
