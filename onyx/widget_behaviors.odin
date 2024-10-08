package onyx

// Some generic behaviors for widgets

button_behavior :: proc(widget: ^Widget) {
	widget.hover_time = animate(
		widget.hover_time,
		0.1,
		.Hovered in widget.state,
	)
	if .Hovered in widget.state {
		core.cursor_type = .Pointing_Hand
	}
	if point_in_box(core.mouse_pos, widget.box) {
		hover_widget(widget)
	}
}

horizontal_slider_behavior :: proc(widget: ^Widget) {
	// widget.hover_time = animate(widget.hover_time, 0.1, .Hovered in widget.state)
	if .Hovered in widget.state {
		core.cursor_type = .Resize_EW
	}
	if point_in_box(core.mouse_pos, widget.box) {
		hover_widget(widget)
	}
}

menu_behavior :: proc(widget: ^Widget) {
	if .Open in widget.state {
		widget.open_time = animate(widget.open_time, 0.2, true)
	} else {
		widget.open_time = 0
	}
	if .Pressed in (widget.state - widget.last_state) {
		widget.state += {.Open}
	}
	widget.hover_time = animate(
		widget.hover_time,
		0.1,
		.Hovered in widget.state,
	)
	if .Hovered in widget.state {
		core.cursor_type = .Pointing_Hand
	}
	if point_in_box(core.mouse_pos, widget.box) {
		hover_widget(widget)
	}
}

get_menu_box :: proc(parent: Box, size: [2]f32, side: Side = .Bottom) -> Box {
	box: Box
	margin := core.style.menu_padding

	view := view_box()

	side := side

	switch side {
	case .Bottom:
		if parent.hi.y + margin + size.y > view.hi.y {
			side = .Top
		}
	case .Top:
		if parent.lo.y - (margin + size.y) < view.lo.y {
			side = .Bottom
		}
	case .Left:
		if parent.lo.x - (margin + size.x) < view.lo.x {
			side = .Right
		}
	case .Right:
		if parent.lo.y + margin + size.x > view.hi.x {
			side = .Left
		}
	}

	switch side {
	case .Bottom:
		box = Box {
			{parent.lo.x, parent.hi.y + margin},
			{parent.lo.x + size.x, parent.hi.y + margin + size.y},
		}
	case .Top:
		box = Box {
			{parent.lo.x, parent.lo.y - (margin + size.y)},
			{parent.lo.x + size.x, parent.lo.y - margin},
		}
	case .Left:
		box = Box {
			{parent.lo.x - (margin + size.x), box_center_y(parent) - size.y / 2},
			{parent.lo.x - margin, box_center_y(parent) + size.y / 2},
		}
	case .Right:
		box = Box {
			{parent.hi.x + margin, box_center_y(parent) - size.y / 2},
			{parent.hi.x + margin + size.x, box_center_y(parent) + size.y / 2},
		}
	}
	return box
}
