package onyx

import "core:math/linalg"

Scrollbar_Info :: struct {
	using _:     Generic_Widget_Info,
	vertical:    bool,
	pos:         f32,
	travel:      f32,
	handle_size: f32,
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

	i, j := int(info.vertical), 1 - int(info.vertical)

	rounding := (widget.box.hi[j] - widget.box.lo[j]) / 2
	handle_size := min(info.handle_size, (widget.box.hi[i] - widget.box.lo[i]))
	travel := (widget.box.hi[i] - widget.box.lo[i]) - handle_size

	handle_box := Box{}
	handle_box.lo[i] = widget.box.lo[i] + (info.pos / info.travel) * travel
	handle_box.hi[i] = handle_box.lo[i] + handle_size

	handle_box.lo[j] = widget.box.lo[j]
	handle_box.hi[j] = widget.box.hi[j]

	if point_in_box(core.mouse_pos, handle_box) {
		hover_widget(widget)
	}

	if widget.visible {
		draw_rounded_box_fill(widget.box, rounding, core.style.color.background)
		draw_rounded_box_fill(handle_box, rounding, core.style.color.substance)
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
