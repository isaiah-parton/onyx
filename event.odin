package onyx

import "core:math"
import "core:math/linalg"

object_was_changed :: proc(object: ^Object) -> bool {
	return .Changed in object.last_state
}

object_was_clicked :: proc(object: ^Object, times: int = 1, with: Mouse_Button = .Left) -> bool {
	return (.Clicked in object.state.previous) && (object.click_count >= times) && (object.click_button == with)
}

object_was_just_changed :: proc(object: ^Object) -> bool {
	return (.Changed in object.state)
}

object_is_dragged :: proc(object: ^Object, beyond: f32 = 1, with: Mouse_Button = .Left) -> bool {
	if .Pressed in object.state && .Dragged not_in object.state {
		if linalg.length(mouse_point() - object.click_point) > beyond {
			object.state += {.Dragged}
		}
	}
	return (.Dragged in object.state) && (object.click_button == with)
}
