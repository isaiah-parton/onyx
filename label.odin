package onyx

import "../vgo"
import "core:fmt"
import "core:math/linalg"

Label :: struct {
	using object: ^Object,
	text_layout:  vgo.Text_Layout,
	align: [2]f32,
	color: vgo.Color,
}

display_label :: proc(self: ^Label) {
	if object_is_visible(self) {
		vgo.fill_text_layout(self.text_layout, linalg.lerp(self.box.lo, self.box.hi, self.align), paint = self.color, align = self.align)
	}
}

label :: proc(
	text: string,
	font_size := global_state.style.default_text_size,
	font := global_state.style.default_font,
	align: [2]f32 = 0,
	color: vgo.Color = colors().content,
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
	self.color = color
	self.align = align
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
