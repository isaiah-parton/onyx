package ronin

import "core:math"
import "core:math/ease"
import "core:math/linalg"

set_cursor :: proc(type: Mouse_Cursor) {
	global_state.cursor_type = type
}

// button_behavior :: proc(self: ^Button) {
// 	self.press_time = animate(
// 		self.press_time,
// 		0.2,
// 		self.active,
// 	)
// 	self.hover_time = animate(
// 		self.hover_time,
// 		0.1,
// 		.Hovered in self.state.current,
// 	)
// 	if .Hovered in self.state.current {
// 		set_cursor(.Pointing_Hand)
// 	}
// 	if point_in_box(global_state.mouse_pos, self.box) {
// 		hover_object(self)
// 	}
// }

horizontal_slider_behavior :: proc(object: ^Object) {
	// object.hover_time = animate(object.hover_time, 0.1, .Hovered in object.state)
	if .Hovered in object.state.current {
		global_state.cursor_type = .Resize_EW
	}
	if point_in_box(global_state.mouse_pos, object.box) {
		hover_object(object)
	}
}

// menu_behavior :: proc(object: ^Object) {
// 	if .Open in object.state {
// 		object.open_time = animate(object.open_time, 0.3, true)
// 	} else {
// 		object.open_time = 0
// 	}
// 	if .Pressed in (object.state - object.last_state) {
// 		object.state += {.Open}
// 	}
// 	object.hover_time = animate(
// 		object.hover_time,
// 		0.1,
// 		.Hovered in object.state,
// 	)
// 	if .Hovered in object.state {
// 		global_state.cursor_type = .Pointing_Hand
// 	}
// 	if point_in_box(global_state.mouse_pos, object.box) {
// 		hover_object(object)
// 	}
// }

get_popup_scale :: proc(size: [2]f32, time: f32) -> f32 {
	return math.lerp(math.lerp(f32(0.8), f32(1.0), linalg.length(size) / linalg.length(global_state.view)), f32(1.0), time)
}

// get_popup_layer_info :: proc(object: ^Object, size: [2]f32, side: Side = .Bottom) -> (info: Layer_Info) {
// 	if object == nil do return
// 	margin := global_state.style.popup_margin
// 	view := view_box()
// 	side := side
// 	parent := object.box
// 	scale := get_popup_scale(size, 1.0)//ease.quadratic_out(object.open_time))
// 	info.id = object.id
// 	info.kind = .Floating
// 	info.scale = [2]f32{scale, scale}

// 	switch side {
// 	case .Bottom:
// 		if parent.hi.y + margin + size.y > view.hi.y {
// 			side = .Top
// 		}
// 	case .Top:
// 		if parent.lo.y - (margin + size.y) < view.lo.y {
// 			side = .Bottom
// 		}
// 	case .Left:
// 		if parent.lo.x - (margin + size.x) < view.lo.x {
// 			side = .Right
// 		}
// 	case .Right:
// 		if parent.lo.y + margin + size.x > view.hi.x {
// 			side = .Left
// 		}
// 	}

// 	switch side {
// 	case .Bottom:
// 		info.box = Box {
// 			{parent.lo.x, parent.hi.y + margin},
// 			{parent.lo.x + size.x, parent.hi.y + margin + size.y},
// 		}
// 		info.origin = {box_center_x(info.box), info.box.lo.y}
// 	case .Top:
// 		info.box = Box {
// 			{parent.lo.x, parent.lo.y - (margin + size.y)},
// 			{parent.lo.x + size.x, parent.lo.y - margin},
// 		}
// 		info.origin = {info.box.lo.x, info.box.hi.y}
// 	case .Left:
// 		info.box = Box {
// 			{parent.lo.x - (margin + size.x), box_center_y(parent) - size.y / 2},
// 			{parent.lo.x - margin, box_center_y(parent) + size.y / 2},
// 		}
// 		info.origin = {info.box.hi.x, box_center_y(info.box)}
// 	case .Right:
// 		info.box = Box {
// 			{parent.hi.x + margin, box_center_y(parent) - size.y / 2},
// 			{parent.hi.x + margin + size.x, box_center_y(parent) + size.y / 2},
// 		}
// 		info.origin = {info.box.lo.x, box_center_y(info.box)}
// 	}

// 	return
// }
