package onyx

import "../vgo"
import "core:fmt"
import "core:math/linalg"

to_ordered_range :: proc(range: [2]$T) -> [2]T {
	range := range
	if range.x > range.y {
		range = range.yx
	}
	return range
}

paragraph :: proc(
	text: string,
	font_size := global_state.style.default_text_size,
	font := global_state.style.default_font,
	align: [2]f32 = 0,
	color: vgo.Color = style().color.content,
	loc := #caller_location,
) {
	object := get_object(hash(loc))
	text_layout := vgo.make_text_layout(
		text,
		font_size,
		font,
	)
	object.box = next_box(text_layout.size)
	if begin_object(object) {
		if object_is_visible(object) {
			text_origin := object.box.lo
			line_height := text_layout.font.line_height * text_layout.font_scale
			for &line, i in text_layout.lines {
				if point_in_box(mouse_point(), {text_origin + line.offset, text_origin + line.offset + line.size}) {
					hover_object(object)
				}
				selection_range := to_ordered_range(text_layout.glyph_selection)
				highlight_range := [2]int {
					max(selection_range.x, line.glyph_range.x),
					min(selection_range.y, line.glyph_range.y),
				}
				if highlight_range.x <= highlight_range.y {
					box := Box {
						text_origin + text_layout.glyphs[highlight_range.x].offset,
						text_origin + text_layout.glyphs[highlight_range.y].offset + {0, line_height},
					}
					box.hi.x +=
						text_layout.font.space_advance *
						text_layout.font_scale *
						f32(i32(selection_range.y > line.glyph_range.y))
					vgo.fill_box(snapped_box(box), paint = color)
				}
			}
			vgo.fill_text_layout(text_layout, text_origin, paint = style().color.accent if .Hovered in object.state.current else style().color.content)
		}
		end_object()
	}
}

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
