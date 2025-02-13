package onyx

Group :: struct {
	id: Id,
	current_state: Object_Status_Set,
	previous_state: Object_Status_Set,
}

begin_group :: proc(allow_sweep: bool = false, loc := #caller_location) -> bool {
	return push_stack(&global_state.group_stack, Group{id = hash(loc)})
}

end_group :: proc() -> (group: ^Group, ok: bool) {
	group, ok = current_group().?
	if !ok {
		return
	}
	pop_stack(&global_state.group_stack)
	if group_below, ok := current_group().?; ok {
		group_below.current_state += group.current_state
		group_below.previous_state += group.previous_state
	}
	return
}

current_group :: proc() -> Maybe(^Group) {
	if global_state.group_stack.height > 0 {
		return &global_state.group_stack.items[global_state.group_stack.height - 1]
	}
	return nil
}
