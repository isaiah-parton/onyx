package onyx

import "../vgo"
import "core:fmt"
import "core:math/linalg"

Label :: struct {
	using object: ^Object,
	text_layout:  vgo.Text_Layout,
}

display_label :: proc(label: ^Label) {
	if begin_object(label) {
		defer end_object()
		if label.visible {
			vgo.fill_text_layout(label.text_layout, label.box.lo, colors().content)
		}
	}
}

label :: proc(
	text: string,
	font := global_state.style.default_font,
	font_size := global_state.style.default_text_size,
	loc := #caller_location,
) {
	object := transient_object()
	label := Label {
		object      = object,
		text_layout = vgo.make_text_layout(
			text,
			font,
			font_size,
		),
	}
	label.box = next_object_box(next_object_size(label.text_layout.size))
	label.desired_size = label.text_layout.size
	object.variant = label
	display_or_add_object(object)
}

header :: proc(text: string, loc := #caller_location) {
	label(
		text,
		font = global_state.style.header_font.? or_else global_state.style.default_font,
		font_size = global_state.style.header_text_size,
		loc = loc,
	)
}
