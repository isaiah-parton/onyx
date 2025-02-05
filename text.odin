package onyx

import "../vgo"
import "tedit"
import "core:strings"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:unicode"

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
