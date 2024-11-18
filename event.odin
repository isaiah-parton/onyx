package onyx

import "core:math"
import "core:math/linalg"

Event_Type :: enum {
	Hover,
	Press,
	Release,
	Click,
	Toggle,
	Set,
}

Object_Tags :: bit_set[0..<64]

Event :: struct {
	type: Event_Type,
	name: string,
	tags: Object_Tags,
	point: [2]f32,
	value: f64,
}

Event_Set_Color :: struct {
	value: [4]u8,
}
Event_Set_Slider :: struct {
	value: f64,
}

object_was_changed :: proc(object: ^Object) -> bool {
	return .Changed in object.last_state
}

object_was_clicked :: proc(object: ^Object, times: int = 1, with: Mouse_Button = .Left) -> bool {
	return (.Clicked in object.last_state) && (object.click_count >= times) && (object.click_button == with)
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

add_event :: proc(object: ^Object, event: Event) {
	event := event
	event.name = object.name
	append(&global_state.events, event)
}
