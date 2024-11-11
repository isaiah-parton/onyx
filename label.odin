package onyx

import "../vgo"
import "core:fmt"
import "core:math/linalg"

Label :: struct {
	using object: ^Object,
	text_layout:  vgo.Text_Layout,
}

display_label :: proc(label: ^Label) {
	if object_is_visible(label) {
		vgo.fill_text_layout(label.text_layout, label.box.lo, colors().content)
	}
}

label :: proc(
	text: string,
	font := global_state.style.default_font,
	font_size := global_state.style.default_text_size,
) {
	object := transient_object()
	if begin_object(object) {
		defer end_object()

		if object.variant == nil {
			object.variant = Label{
				object = object,
			}
		}
		label := &object.variant.(Label)
		label.text_layout = vgo.make_text_layout(
			text,
			font,
			font_size,
		)
		label.desired_size = label.text_layout.size
	}
}

header :: proc(text: string) {
	label(
		text,
		font = global_state.style.header_font.? or_else global_state.style.default_font,
		font_size = global_state.style.header_text_size,
	)
}
