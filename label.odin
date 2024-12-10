package onyx

import "../vgo"
import "core:fmt"
import "core:math/linalg"

Label :: struct {
	using object: ^Object,
	text_layout:  vgo.Text_Layout,
}

display_label :: proc(self: ^Label) {
	if object_is_visible(self) {
		vgo.fill_text_layout(self.text_layout, self.box.lo, paint = colors().content)
	}
}

label :: proc(
	text: string,
	font_size := global_state.style.default_text_size,
	font := global_state.style.default_font,
) {
	object := transient_object()
	if object.variant == nil {
		object.variant = Label{
			object = object,
		}
	}
	self := &object.variant.(Label)
	self.placement = next_user_placement()
	self.text_layout = vgo.make_text_layout(
		text,
		font_size,
		font,
	)
	self.metrics.desired_size = self.text_layout.size
	if begin_object(object) {
		defer end_object()
	}
}

header :: proc(text: string) {
	label(
		text,
		font_size = global_state.style.header_text_size,
		font = global_state.style.header_font.? or_else global_state.style.default_font,
	)
}
