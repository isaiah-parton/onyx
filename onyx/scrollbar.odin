package onyx

import "core:math/linalg"

Scrollbar_Info :: struct {
	using _:     Generic_Widget_Info,
	vertical:    bool,
	pos:         f32,
	travel:      f32,
	handle_size: f32,
	make_visible: bool,
}

Scrollbar_Result :: struct {
	using _: Generic_Widget_Result,
	pos:     Maybe(f32),
}

make_scrollbar :: proc(info: Scrollbar_Info, loc := #caller_location) -> Scrollbar_Info {
	info := info
	info.id = hash(loc)
	info.desired_size[1 - int(info.vertical)] = core.style.shape.scrollbar_thickness
	return info
}

add_scrollbar :: proc(info: Scrollbar_Info) -> (result: Scrollbar_Result) {
	widget, ok := begin_widget(info)
	if !ok do return

	widget.draggable = true

	// Virtually swizzle coordinates
	// TODO: Remove this and actually swizzle them for better readability
	i, j := int(info.vertical), 1 - int(info.vertical)

	handle_size := min(info.handle_size, (widget.box.hi[i] - widget.box.lo[i]))
	travel := (widget.box.hi[i] - widget.box.lo[i]) - handle_size

	handle_box := Box{}
	handle_box.lo[i] = widget.box.lo[i] + clamp(info.pos / info.travel, 0, 1) * travel
	handle_box.hi[i] = handle_box.lo[i] + handle_size

	handle_box.lo[j] = widget.box.lo[j]
	handle_box.hi[j] = widget.box.hi[j]

	if point_in_box(core.mouse_pos, widget.box) {
		hover_widget(widget)
	}
	widget.hover_time = animate(widget.hover_time, 0.15, info.make_visible || .Hovered in widget.state)

	if widget.visible {
		draw_box_stroke(widget.box, 1, fade(core.style.color.substance, widget.hover_time))
		draw_box_fill(widget.box, fade(core.style.color.substance, 0.5 * widget.hover_time))
		draw_box_fill(handle_box, fade(core.style.color.content, 0.5 * widget.hover_time))
	}

	if .Pressed in widget.state {
		if .Pressed not_in widget.last_state {
			core.drag_offset = core.mouse_pos - handle_box.lo
		}
		result.pos =
			clamp(((core.mouse_pos[i] - core.drag_offset[i]) - widget.box.lo[i]) / travel, 0, 1) *
			info.travel
	}

	end_widget()
	return
}

do_scrollbar :: proc(info: Scrollbar_Info, loc := #caller_location) -> Scrollbar_Result {
	return add_scrollbar(make_scrollbar(info, loc))
}
