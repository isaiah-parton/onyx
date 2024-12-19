package onyx

import "../vgo"
import "core:fmt"
import "core:math/linalg"

Scrollbar :: struct {
	using object: ^Object,
	vertical:     bool,
	pos:          f32,
	travel:       f32,
	handle_size:  f32,
	make_visible: bool,
	changed:      bool,
}

scrollbar :: proc(
	pos: ^f32,
	travel, handle_size: f32,
	box: Box,
	make_visible: bool = false,
	vertical: bool = false,
	loc := #caller_location,
) -> (changed: bool) {
	object := persistent_object(hash(loc))
	if object.variant == nil {
		object.variant = Scrollbar {
			object = object,
		}
	}
	self := &object.variant.(Scrollbar)
	self.placement = box
	self.travel = travel
	self.handle_size = handle_size
	self.make_visible = make_visible
	self.vertical = vertical
	if begin_object(object) {
		defer end_object()
		if object_was_changed(self) {
			pos^ = self.pos
			changed = true
		} else if pos != nil {
			self.pos = pos^
		}
	}
	return
}

display_scrollbar :: proc(self: ^Scrollbar) {
	handle_object_click(self, sticky = true)

	if point_in_box(mouse_point(), self.box) {
		hover_object(self)
	}

	i := int(self.vertical)
	j := 1 - i

	rounding := (self.box.hi[j] - self.box.lo[j]) / 2

	handle_time := self.pos / self.travel
	handle_travel_distance := (self.box.hi[i] - self.box.lo[i]) - self.handle_size

	handle_box: Box
	handle_box.lo[i] = self.box.lo[i] + handle_travel_distance * handle_time
	handle_box.hi[i] = handle_box.lo[i] + self.handle_size
	handle_box.lo[j] = self.box.lo[j]
	handle_box.hi[j] = self.box.hi[j]

	if object_is_visible(self) {
		vgo.fill_box(
			handle_box,
			rounding,
			paint = colors().substance if .Hovered in self.state.current else colors().fg,
		)
	}

	if .Pressed in self.state.current {
		if .Pressed not_in self.state.previous {
			global_state.drag_offset = handle_box.lo - mouse_point()
		}
		time := ((mouse_point()[i] + global_state.drag_offset[i]) - self.box.lo[i]) / handle_travel_distance
		self.pos = self.travel * clamp(time, 0, 1)
		add_object_state_for_next_frame(self, {.Changed})
	}
}
