package onyx

import "../vgo"
import "core:fmt"
import "core:math/linalg"

scrollbar :: proc(
	pos: ^f32,
	travel, handle_size: f32,
	box: Box,
	make_visible: bool = false,
	vertical: bool = false,
	loc := #caller_location,
) -> (changed: bool) {
	if pos == nil {
		return
	}
	object := persistent_object(hash(loc))
	if begin_object(object) {
		defer end_object()

		object.box = box

		handle_object_click(object, sticky = true)

		if point_in_box(mouse_point(), object.box) {
			hover_object(object)
		}

		i := int(vertical)
		j := 1 - i

		rounding := (object.box.hi[j] - object.box.lo[j]) / 2

		handle_time := pos^ / travel
		handle_travel_distance := (object.box.hi[i] - object.box.lo[i]) - handle_size

		handle_box: Box
		handle_box.lo[i] = object.box.lo[i] + max(0, handle_travel_distance * handle_time)
		handle_box.hi[i] = min(handle_box.lo[i] + handle_size, object.box.hi[i])
		handle_box.lo[j] = object.box.lo[j]
		handle_box.hi[j] = object.box.hi[j]

		if object_is_visible(object) {
			vgo.fill_box(
				handle_box,
				rounding,
				paint = colors().accent if .Hovered in object.state.current else colors().substance,
			)
		}

		if .Pressed in object.state.current {
			if .Pressed not_in object.state.previous {
				global_state.drag_offset = handle_box.lo - mouse_point()
			}
			time := ((mouse_point()[i] + global_state.drag_offset[i]) - object.box.lo[i]) / handle_travel_distance
			pos^ = travel * clamp(time, f32(0), f32(1))
			changed = true
		}
	}
	return
}
