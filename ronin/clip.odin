package ronin

push_clip :: proc(box: Box) {
	push_stack(&global_state.clip_stack, box)
}
pop_clip :: proc() {
	pop_stack(&global_state.clip_stack)
}
current_clip :: proc() -> Box {
	if global_state.clip_stack.height > 0 {
		return global_state.clip_stack.items[global_state.clip_stack.height - 1]
	}
	return view_box()
}
