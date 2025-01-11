package onyx

import "../vgo"
import "core:fmt"
import "core:math/linalg"

label :: proc(
	text: string,
	font_size := global_state.style.default_text_size,
	font := global_state.style.default_font,
	align: [2]f32 = 0,
	color: vgo.Color = colors().content,
) {
	object := make_transient_object()
	text_layout := vgo.make_text_layout(
		text,
		font_size,
		font,
	)
	object.size = text_layout.size
	object.box = next_box(object.size)
	if begin_object(object) {
		if object_is_visible(object) {
			vgo.fill_text_layout(text_layout, linalg.lerp(object.box.lo, object.box.hi, align), paint = color, align = align)
		}
		end_object()
	}
}

header :: proc(text: string) {
	label(
		text,
		font_size = global_state.style.header_text_size,
		font = global_state.style.header_font.? or_else global_state.style.default_font,
	)
}
