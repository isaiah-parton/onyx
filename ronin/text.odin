package ronin

import kn "local:katana"
import "tedit"
import "core:strings"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:unicode"

Text_Content_Builder :: struct {
	buf: [dynamic]u8,
	needs_new_line: bool,
}

text_content_builder_reset :: proc(b: ^Text_Content_Builder) {
	b.needs_new_line = false
	clear(&b.buf)
}

text_content_builder_write :: proc(b: ^Text_Content_Builder, s: string, range: [2]int) {
	if range.x == range.y {
		return
	}
	if b.needs_new_line {
		append(&b.buf, '\n')
		b.needs_new_line = false
	}
	append(&b.buf, s[range.x:range.y])
	if range.y == len(s) {
		b.needs_new_line = true
	}
}

add_global_text_content :: proc(s: string, range: [2]int) {
	text_content_builder_write(&global_state.text_content_builder, s, range)
}

to_ordered_range :: proc(range: [2]$T) -> [2]T {
	range := range
	if range.x > range.y {
		range.x, range.y = range.y, range.x
	}
	return range
}

point_inside_text :: proc(point: [2]f32, origin: [2]f32, text: kn.Text) -> bool {
	if !point_in_box(point, Box{origin, origin + text.size}) {
		return false
	}
	for &line in text.lines {
		if point_in_box(point, Box{origin + line.offset, origin + line.offset + line.size}) {
			return true
		}
	}
	return false
}

text :: proc(
	content: string,
	font_size := global_state.style.default_text_size,
	font := global_state.style.default_font,
	align: [2]f32 = 0,
	color: kn.Color = get_current_style().color.content,
	loc := #caller_location,
) {
	self := get_object(hash(loc))
	self.flags += {.Sticky_Hover, .Sticky_Press}
	layout := get_current_layout()
	text := kn.make_text(
		content,
		font_size,
		font,
		max_size = box_size(layout.box),
		wrap = .Word,
		selection = self.input.editor.selection,
	)
	self.size = text.size
	if do_object(self) {
		if object_is_visible(self) {
			style := get_current_style()
			text_origin := self.box.lo
			text := kn.make_selectable(text, mouse_point() - text_origin)
			if text.selection.valid {
				hover_object(self)
			}
			if .Pressed in self.state.current {
				self.state.current += {.Active}
			}
			if .Active in self.state.current {
				if global_state.last_focused_object != global_state.focused_object &&
				   global_state.focused_object != self.id &&
				   !key_down(.Left_Control) {
					self.state.current -= {.Active}
				}
				draw_text_highlight(&text, text_origin, kn.fade(style.color.accent, 1.0 / 3.0))
				text_mouse_selection(self, content, &text)
				add_global_text_content(content, to_ordered_range(self.input.editor.selection))
			}
			kn.add_text(text, text_origin, paint = color)
			if .Hovered in self.state.current {
				set_cursor(.I_Beam)
			}
		}
	}
}

label :: proc(
	text: string,
	font_size := global_state.style.default_text_size,
	font := global_state.style.default_font,
	color: kn.Color = get_current_style().color.content,
	loc := #caller_location,
) {
	text_layout := kn.make_text(
		text,
		font_size,
		font,
	)
	self := get_object(hash(loc))
	self.size = text_layout.size
	self.size_is_fixed = true
	if begin_object(self) {
		if object_is_visible(self) {
			if point_in_box(mouse_point(), self.box) {
				hover_object(self)
			}
			kn.add_text(text_layout, self.box.lo, paint = color)
		}
		end_object()
	}
}

h1 :: proc(content: string) {
	text(
		content,
		font_size = global_state.style.header_text_size,
		font = global_state.style.header_font.? or_else global_state.style.default_font,
	)
}

icon :: proc(which_one: rune, size: f32 = global_state.style.icon_size, loc := #caller_location) {
	style := get_current_style()
	font := style.icon_font
	if glyph, ok := kn.get_font_glyph(font, which_one); ok {
		self := get_object(hash(loc))
		self.size = {glyph.advance * size, font.line_height * size}
		if do_object(self) {
			if object_is_visible(self) {
				kn.add_glyph(glyph, size, linalg.floor(box_center(self.box)) - size / 2, style.color.content)
			}
		}
	}
}

text_mouse_selection :: proc(object: ^Object, data: string, text: ^kn.Selectable_Text) {
	is_separator :: proc(r: rune) -> bool {
		return !unicode.is_alpha(r) && !unicode.is_number(r)
	}

	last_selection := object.input.editor.selection
	if .Pressed in object.state.current && text.selection.index >= 0 {
		if .Pressed not_in object.state.previous {
			object.input.anchor = text.selection.index
			if object.click.count == 3 {
				object.input.editor.selection = {len(data), 0}
				// tedit.editor_execute(&object.input.editor, .Select_All)
			} else {
				object.input.editor.selection = {
					text.selection.index,
					text.selection.index,
				}
			}
		}
		switch object.click.count {
		case 2:
			allow_precision := text.selection.index != object.input.anchor
			if text.selection.index <= object.input.anchor {
				object.input.editor.selection[0] = text.selection.index if (allow_precision && is_separator(rune(data[text.selection.index]))) else max(
					0,
					strings.last_index_proc(
						data[:text.selection.index],
						is_separator,
					) +
					1,
				)
				object.input.editor.selection[1] = strings.index_proc(
					data[object.input.anchor:],
					is_separator,
				)
				if object.input.editor.selection[1] == -1 {
					object.input.editor.selection[1] = len(data)
				} else {
					object.input.editor.selection[1] += object.input.anchor
				}
			} else {
				object.input.editor.selection[1] = max(
					0,
					strings.last_index_proc(
						data[:object.input.anchor],
						is_separator,
					) +
					1,
				)
				// `text.selection.index - 1` is safe as long as `text.selection.index > object.input.anchor`
				object.input.editor.selection[0] = 0 if (allow_precision && is_separator(rune(data[text.selection.index - 1]))) else strings.index_proc(
					data[text.selection.index:],
					is_separator,
				)
				if object.input.editor.selection[0] == -1 {
					object.input.editor.selection[0] =
						len(data)
				} else {
					object.input.editor.selection[0] += text.selection.index
				}
			}
		case 1:
			object.input.editor.selection[0] = text.selection.index
		}
	}
}
