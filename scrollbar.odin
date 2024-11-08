package onyx

import "core:math/linalg"
import "../vgo"

Scrollbar :: struct {
	vertical:     bool,
	pos:          ^f32,
	travel:       f32,
	handle_size:  f32,
	make_visible: bool,
	changed:      bool,
}

scrollbar :: proc(pos: ^f32, travel, handle_size: f32, vertical: bool = false, loc := #caller_location) {
	object := persistent_object(hash(loc))
	if begin_object(object) {
		defer end_object()


	}
}
