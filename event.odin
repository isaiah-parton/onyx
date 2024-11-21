package onyx

import "core:math"
import "core:math/linalg"

object_was_changed :: proc(object: ^Object) -> bool {
	return .Changed in object.state.previous
}

object_was_clicked :: proc(object: ^Object, times: int = 1, with: Mouse_Button = .Left) -> bool {
	return (.Clicked in object.state.previous) && (object.input.click_count >= times) && (object.input.click_mouse_button == with)
}

object_was_just_changed :: proc(object: ^Object) -> bool {
	return (.Changed in object.state.current)
}

object_is_dragged :: proc(object: ^Object, beyond: f32 = 1, with: Mouse_Button = .Left) -> bool {
	if .Pressed in object.state.current && .Dragged not_in object.state.current {
		if linalg.length(mouse_point() - object.input.click_point) > beyond {
			object.state.current += {.Dragged}
		}
	}
	return (.Dragged in object.state.current) && (object.input.click_mouse_button == with)
}
