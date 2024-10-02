package onyx

import "core:math/linalg"

Scrollbar_Info :: struct {
	using _:      Widget_Info,
	vertical:     bool,
	pos:          ^f32,
	travel:       f32,
	handle_size:  f32,
	make_visible: bool,
}

init_scrollbar :: proc(info: ^Scrollbar_Info, loc := #caller_location) -> bool {
	if info.pos == nil {
		return false
	}
	info.id = hash(loc)
	info.self = get_widget(info.id) or_return
	info.sticky = true
	info.desired_size[1 - int(info.vertical)] = core.style.shape.scrollbar_thickness
	return true
}

add_scrollbar :: proc(using info: ^Scrollbar_Info) -> bool {
	begin_widget(info) or_return
	defer end_widget()

	// Virtually swizzle coordinates
	// TODO: Remove this and actually swizzle them for better readability
	i, j := int(info.vertical), 1 - int(info.vertical)

	_box := self.box

	_box.lo[j] += (_box.hi[j] - _box.lo[j]) * (0.5 * (1 - self.hover_time))

	_handle_size := min(handle_size, (_box.hi[i] - _box.lo[i]))
	_travel := (_box.hi[i] - _box.lo[i]) - handle_size

	handle_box := Box{}
	handle_box.lo[i] = _box.lo[i] + clamp(info.pos^ / info.travel, 0, 1) * _travel
	handle_box.hi[i] = handle_box.lo[i] + _handle_size

	handle_box.lo[j] = _box.lo[j]
	handle_box.hi[j] = _box.hi[j]

	if point_in_box(core.mouse_pos, self.box) {
		hover_widget(self)
	}
	self.hover_time = animate(self.hover_time, 0.15, .Hovered in self.state)
	self.focus_time = animate(self.focus_time, 0.15, make_visible || .Hovered in self.state)

	if self.visible {
		draw_box_stroke(_box, 1, fade(core.style.color.substance, self.focus_time))
		draw_box_fill(_box, fade(core.style.color.substance, 0.5 * self.focus_time))
		draw_box_fill(handle_box, fade(core.style.color.content, 0.5 * self.focus_time))
	}

	if .Pressed in self.state {
		if .Pressed not_in self.last_state {
			core.drag_offset = core.mouse_pos - handle_box.lo
		}
		pos^ =
			clamp(((core.mouse_pos[i] - core.drag_offset[i]) - _box.lo[i]) / _travel, 0, 1) *
			travel
	}

	return true
}

scrollbar :: proc(info: Scrollbar_Info, loc := #caller_location) -> Scrollbar_Info {
	info := info
	init_scrollbar(&info, loc)
	add_scrollbar(&info)
	return info
}
