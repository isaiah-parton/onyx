package onyx

button_behavior :: proc(widget: ^Widget) {
	widget.hover_time = animate(widget.hover_time, 0.1, .Hovered in widget.state)
	if .Hovered in widget.state {
		core.cursor_type = .POINTING_HAND
	}
	if point_in_box(core.mouse_pos, widget.box) {
		widget.try_hover = true
	}
}

menu_behavior :: proc(widget: ^Widget) {
	kind := widget_kind(widget, Menu_Widget_Kind)
	if .Open in widget.state {
		kind.open_time = animate(kind.open_time, 0.2, .Open in widget.state)
	} else {
		kind.open_time = 0
	}
	if .Pressed in (widget.state - widget.last_state) {
		widget.state += {.Open}
	}
	button_behavior(widget)
}