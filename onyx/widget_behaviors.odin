package onyx

// Some generic behaviors for widgets

button_behavior :: proc(widget: ^Widget) {
	widget.hover_time = animate(widget.hover_time, 0.1, .Hovered in widget.state)
	if .Hovered in widget.state {
		core.cursor_type = .Pointing_Hand
	}
	if point_in_box(core.mouse_pos, widget.box) {
		hover_widget(widget)
	}
}

menu_behavior :: proc(widget: ^Widget) {
	kind := widget_kind(widget, Menu_Widget_Kind)
	if .Open in widget.state {
		kind.open_time = animate(kind.open_time, 0.2, true)
	} else {
		kind.open_time = 0
	}
	if .Pressed in (widget.state - widget.last_state) {
		widget.state += {.Open}
	}
	button_behavior(widget)
}
