package onyx

Placement_Options :: struct {
	size:  [2]Layout_Size,
	align:  Align,
	margin: [4]f32,
}

current_placement_options :: proc() -> ^Placement_Options {
	return &global_state.placement_options_stack.items[max(0, global_state.placement_options_stack.height - 1)]
}

push_placement_options :: proc() {
	push_stack(&global_state.placement_options_stack, current_placement_options()^)
}

pop_placement_options :: proc() {
	pop_stack(&global_state.placement_options_stack)
}
