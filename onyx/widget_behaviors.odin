package onyx

import "core:math"
import "core:math/ease"
import "core:math/linalg"

// Some generic behaviors for widgets

button_behavior :: proc(widget: ^Widget) {
	widget.hover_time = animate(
		widget.hover_time,
		0.1,
		.Hovered in widget.state,
	)
	widget.press_time = animate(
		widget.press_time,
		0.1,
		.Pressed in widget.state,
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
		widget.open_time = animate(widget.open_time, 0.3, true)
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

get_popup_scale :: proc(size: [2]f32, time: f32) -> f32 {
	return math.lerp(math.lerp(f32(0.9), f32(1.0), linalg.length(size) / linalg.length(core.view)), f32(1.0), time)
}

get_popup_layer_info :: proc(widget: ^Widget, size: [2]f32, side: Side = .Bottom) -> (info: Layer_Info) {
	if widget == nil do return
	margin := core.style.popup_margin
	view := view_box()
	side := side
	parent := widget.box
	scale := get_popup_scale(size, ease.quadratic_out(widget.open_time))
	info.id = widget.id
	info.kind = .Floating
	info.scale = [2]f32{scale, scale}

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
		info.box = Box {
			{parent.lo.x, parent.hi.y + margin},
			{parent.lo.x + size.x, parent.hi.y + margin + size.y},
		}
		info.origin = info.box.lo
	case .Top:
		info.box = Box {
			{parent.lo.x, parent.lo.y - (margin + size.y)},
			{parent.lo.x + size.x, parent.lo.y - margin},
		}
		info.origin = {info.box.lo.x, info.box.hi.y}
	case .Left:
		info.box = Box {
			{parent.lo.x - (margin + size.x), box_center_y(parent) - size.y / 2},
			{parent.lo.x - margin, box_center_y(parent) + size.y / 2},
		}
		info.origin = {info.box.hi.x, box_center_y(info.box)}
	case .Right:
		info.box = Box {
			{parent.hi.x + margin, box_center_y(parent) - size.y / 2},
			{parent.hi.x + margin + size.x, box_center_y(parent) + size.y / 2},
		}
		info.origin = {info.box.lo.x, box_center_y(info.box)}
	}

	return
}
