package onyx

import "core:math/linalg"
import "../vgo"

Scrollbar :: struct {
	using object: ^Object,
	vertical:     bool,
	pos:          ^f32,
	travel:       f32,
	handle_size:  f32,
	make_visible: bool,
	changed:      bool,
}

scrollbar :: proc(pos: ^f32, travel, handle_size: f32, box: Box, make_visible: bool = false, vertical: bool = false, loc := #caller_location) -> bool {
	object := persistent_object(hash(loc))
	if object.variant == nil {
		object.variant = Scrollbar{
			object = object,
		}
	}
	self := &object.variant.(Scrollbar)
	if begin_object(object) {
		defer end_object()


	}
	return true
}

display_scrollbar :: proc(self: ^Scrollbar) {

}
