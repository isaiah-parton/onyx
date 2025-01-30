package onyx

import "../vgo"
import "core:fmt"
import "core:math/linalg"

label :: proc(
	text: string,
	font_size := global_state.style.default_text_size,
	font := global_state.style.default_font,
	align: [2]f32 = 0,
	color: vgo.Color = style().color.content,
) {
	text_layout := vgo.make_text_layout(
		text,
		font_size,
		font,
	)
	box := next_box(text_layout.size)
	if get_clip(current_clip(), box) != .Full {
		vgo.fill_text_layout(text_layout, linalg.lerp(box.lo, box.hi, align), paint = color, align = align)
	}
}

header :: proc(text: string) {
	label(
		text,
		font_size = global_state.style.header_text_size,
		font = global_state.style.header_font.? or_else global_state.style.default_font,
	)
}

icon :: proc(which_one: rune, size: f32 = global_state.style.icon_size) -> bool {
	font := style().icon_font
	glyph := vgo.get_font_glyph(font, which_one) or_return
	box := next_box({glyph.advance * size, font.line_height * size})
	if get_clip(current_clip(), box) != .Full {
		vgo.fill_glyph(glyph, size, linalg.floor(box_center(box) - size / 2), style().color.content)
	}
	return true
}
