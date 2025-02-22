package onyx

import "../vgo"
import "tedit"
import "core:strings"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:unicode"

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
	padding: [2]f32 = 0,
	color: vgo.Color = style().color.content,
	loc := #caller_location,
) {
	text_layout := vgo.make_text_layout(
		text,
		font_size,
		font,
	)
	object := get_object(hash(loc))
	object.size = text_layout.size
	object.box = next_box(object.size)
	if begin_object(object) {
		if object_is_visible(object) {
			if point_in_box(mouse_point(), object.box) {
				hover_object(object)
			}
			box := shrink_box(object.box, padding)
			vgo.fill_text_layout(text_layout, linalg.lerp(box.lo, box.hi, align), paint = color, align = align)
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

icon :: proc(which_one: rune, size: f32 = global_state.style.icon_size) -> bool {
	font := style().icon_font
	glyph := vgo.get_font_glyph(font, which_one) or_return
	box := next_box({glyph.advance * size, font.line_height * size})
	if get_clip(current_clip(), box) != .Full {
		vgo.fill_glyph(glyph, size, linalg.floor(box_center(box)) - size / 2, style().color.content)
	}
	return true
}

text_mouse_selection :: proc(object: ^Object, content: string, layout: ^vgo.Text_Layout) {
	is_separator :: proc(r: rune) -> bool {
		return !unicode.is_alpha(r) && !unicode.is_number(r)
	}

	last_selection := object.input.editor.selection
	if .Pressed in object.state.current && layout.mouse_index >= 0 {
		if .Pressed not_in object.state.previous {
			object.input.anchor = layout.mouse_index
			if object.click.count == 3 {
				tedit.editor_execute(&object.input.editor, .Select_All)
			} else {
				object.input.editor.selection = {
					layout.mouse_index,
					layout.mouse_index,
				}
			}
		}
		switch object.click.count {
		case 2:
			if layout.mouse_index < object.input.anchor {
				if content[layout.mouse_index] == ' ' {
					object.input.editor.selection[0] = layout.mouse_index
				} else {
					object.input.editor.selection[0] = max(
						0,
						strings.last_index_proc(
							content[:layout.mouse_index],
							is_separator,
						) +
						1,
					)
				}
				object.input.editor.selection[1] = strings.index_proc(
					content[object.input.anchor:],
					is_separator,
				)
				if object.input.editor.selection[1] == -1 {
					object.input.editor.selection[1] = len(content)
				} else {
					object.input.editor.selection[1] += object.input.anchor
				}
			} else {
				object.input.editor.selection[1] = max(
					0,
					strings.last_index_proc(
						content[:object.input.anchor],
						is_separator,
					) +
					1,
				)
				if (layout.mouse_index > 0 &&
					   content[layout.mouse_index - 1] == ' ') {
					object.input.editor.selection[0] = 0
				} else {
					object.input.editor.selection[0] = strings.index_proc(
						content[layout.mouse_index:],
						is_separator,
					)
				}
				if object.input.editor.selection[0] == -1 {
					object.input.editor.selection[0] =
						len(content) - layout.mouse_index
				}
				object.input.editor.selection[0] += layout.mouse_index
			}
		case 1:
			object.input.editor.selection[0] = layout.mouse_index
		}
	}
}
