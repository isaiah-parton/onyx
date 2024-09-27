package onyx

// Some generic behaviors for widgets

button_behavior :: proc(widget: ^Widget) {
	widget.button.hover_time = animate(widget.button.hover_time, 0.1, .Hovered in widget.state)
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
		widget.menu.open_time = animate(widget.menu.open_time, 0.2, true)
	} else {
		widget.menu.open_time = 0
	}
	if .Pressed in (widget.state - widget.last_state) {
		widget.state += {.Open}
	}
	widget.menu.hover_time = animate(widget.menu.hover_time, 0.1, .Hovered in widget.state)
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
	#partial switch side {
	case .Bottom:
		box = Box{
			{parent.lo.x, parent.hi.y + margin},
			{parent.lo.x + size.x, parent.hi.y + margin + size.y},
		}
	}
	return box
}
