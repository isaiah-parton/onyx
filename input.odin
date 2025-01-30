package onyx

import "../vgo"
import "base:intrinsics"
import "base:runtime"
import "core:fmt"
import "core:io"
import "core:math"
import "core:math/linalg"
import "core:mem"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:time"
import "core:unicode"
import "tedit"

Input_Decal :: enum {
	None,
	Check,
	Spinner,
}

Input_State :: struct {
	editor:  tedit.Editor,
	builder: strings.Builder,
	anchor:  int,
	offset:  [2]f32,
	last_mouse_index: int,
	action_time: time.Time,
}

input_select_all :: proc(object: ^Object) {
	object.input.editor.selection = {len(object.input.builder.buf), 0}
}

destroy_input :: proc(input: ^Input_State) {
	tedit.destroy_editor(&input.editor)
	strings.builder_destroy(&input.builder)
}

activate_input :: proc(object: ^Object) {
	object.state.current += {.Active}
}

Input_Result :: struct {
	confirmed: bool,
	changed:   bool,
}

Input_Flag :: enum {
	Undecorated,
	Obfuscated,
	Multiline,
	Monospace,
	Hidden_Unless_Active,
	Select_All,
}

Input_Flags :: bit_set[Input_Flag;u8]

write_input_value :: proc(w: io.Writer, value: ^$T, format: string) {
	when T == string {
		io.write_string(w, value^)
	} else when T == cstring {
		fmt.wprint(w, value^)
	} else when intrinsics.type_is_numeric(T) {
		fmt.wprintf(w, format, value^)
	}
}

input :: proc(
	content: ^$T,
	format: string = "%v",
	prefix: string = "",
	placeholder: string = "",
	flags: Input_Flags = {},
	loc := #caller_location,
) -> (
	result: Input_Result,
) where intrinsics.type_is_string(T) ||
	intrinsics.type_is_numeric(T) {
	if content == nil {
		return {}
	}

	object := persistent_object(hash(loc))
	if .Is_Input not_in object.flags {
		object.flags += {.Is_Input}
		object.input.builder = strings.builder_make()
	}

	if begin_object(object) {
		object.box = next_box({})

		content_string: string
		if .Active not_in object.state.current {
			strings.builder_reset(&object.input.builder)
			write_input_value(strings.to_writer(&object.input.builder), content, format)
		} else {
			// b := strings.builder_make(allocator = context.temp_allocator)
			// content_string = strings.to_string(b)
		}
		content_string = strings.to_string(object.input.builder)

		if object.input.editor.builder == nil {
			tedit.make_editor(&object.input.editor, context.allocator, context.allocator)
			tedit.begin(&object.input.editor, 0, &object.input.builder)
			object.input.editor.set_clipboard = __set_clipboard_string
			object.input.editor.get_clipboard = __get_clipboard_string
		}

		multiline := .Multiline in flags
		obfuscated := .Obfuscated in flags
		monospace := .Monospace in flags

		style := style()
		text_size := style.content_text_size
		text_font := (style.monospace_font if (monospace) else style.default_font)
		vgo.set_font(text_font)

		text_origin: [2]f32
		if multiline {
			text_origin = object.box.lo + global_state.style.text_padding + {0, 2}
		} else {
			text_origin = {
				object.box.lo.x + global_state.style.text_padding.x,
				box_center_y(object.box) - text_font.line_height * text_size * 0.5,
			}
		}
		result.confirmed =
			result.confirmed || (!(!key_down(.Left_Control) && multiline) && key_pressed(.Enter))

		content_layout, prefix_layout: vgo.Text_Layout
		if len(prefix) > 0 {
			prefix_layout = vgo.make_text_layout(prefix, text_size)
			text_origin.x += prefix_layout.size.x
		}

		if !((.Hidden_Unless_Active in flags) && (.Active not_in object.state.current)) {

			is_visible := object_is_visible(object)

			if point_in_box(mouse_point(), object.box) {
				hover_object(object)
			}

			if .Hovered in object.state.current {
				set_cursor(.I_Beam)
			}

			if .Active in object.state.current {
				if global_state.last_focused_object != global_state.focused_object &&
				   global_state.focused_object != object.id &&
				   !key_down(.Left_Control) {
					object.state.current -= {.Active}
				}
			} else if .Pressed in object.state.current {
				object.state.current += {.Active}
			}

			if key_pressed(.Escape) {
				object.state.current -= {.Active}
			} else if .Active in lost_state(object.state) {
				object.state.current += {.Changed}
			}

			if is_visible {
				options := vgo.DEFAULT_TEXT_OPTIONS
				options.obfuscated = obfuscated
				content_layout = vgo.make_text_layout(
					content_string,
					text_size,
					selection = object.input.editor.selection,
					options = options,
					local_mouse = mouse_point() - (text_origin - object.input.offset),
				)
			}

			if .Pressed not_in object.state.current && object.input.last_mouse_index != content_layout.mouse_index {
				object.click.count = 0
			}
			object.input.last_mouse_index = content_layout.mouse_index

			if .Active in object.state.current {
				if .Active not_in object.state.previous {
					strings.builder_reset(&object.input.builder)
					write_input_value(strings.to_writer(&object.input.builder), content, format)
					if .Select_All in flags {
						tedit.editor_execute(&object.input.editor, .Select_All)
					}
				}

				if key_pressed(.Enter) && !(.Multiline in flags && !key_down(.Left_Control)) {
					result.confirmed = true
				}

				cmd: tedit.Command
				control_down := key_down(.Left_Control) || key_down(.Right_Control)
				shift_down := key_down(.Left_Shift) || key_down(.Right_Shift)
				if control_down {
					if key_pressed(.A) do cmd = .Select_All
					if key_pressed(.C) do cmd = .Copy
					if key_pressed(.V) do cmd = .Paste
					if key_pressed(.X) do cmd = .Cut
					if key_pressed(.Z) do cmd = .Undo
					if key_pressed(.Y) do cmd = .Redo
				}
				if len(global_state.runes) > 0 {
					for char, c in global_state.runes {
						tedit.input_runes(&object.input.editor, {char})
						draw_frames(1)
						object.state.current += {.Changed}
					}
				}
				if key_pressed(.Backspace) do cmd = .Delete_Word_Left if control_down else .Backspace
				if key_pressed(.Delete) do cmd = .Delete_Word_Right if control_down else .Delete
				if key_pressed(.Enter) {
					cmd = .New_Line
					if multiline {
						if control_down {
							result.confirmed = true
						}
					} else {
						result.confirmed = true
					}
				}
				if key_pressed(.Left) {
					if shift_down do cmd = .Select_Word_Left if control_down else .Select_Left
					else do cmd = .Word_Left if control_down else .Left
				}
				if key_pressed(.Right) {
					if shift_down do cmd = .Select_Word_Right if control_down else .Select_Right
					else do cmd = .Word_Right if control_down else .Right
				}
				if key_pressed(.Up) {
					if shift_down do cmd = .Select_Up
					else do cmd = .Up
				}
				if key_pressed(.Down) {
					if shift_down do cmd = .Select_Down
					else do cmd = .Down
				}
				if key_pressed(.Home) {
					cmd = .Select_Line_Start if control_down else .Line_Start
				}
				if key_pressed(.End) {
					cmd = .Select_Line_End if control_down else .Line_End
				}
				if !multiline && (cmd in tedit.MULTILINE_COMMANDS) {
					cmd = .None
				}
				if cmd != .None {
					tedit.editor_execute(&object.input.editor, cmd)
					if cmd in tedit.EDIT_COMMANDS {
						object.state.current += {.Changed}
					}
					draw_frames(1)
				}
			}

			is_separator :: proc(r: rune) -> bool {
				return !unicode.is_alpha(r) && !unicode.is_number(r)
			}

			last_selection := object.input.editor.selection
			if .Pressed in object.state.current && content_layout.mouse_index >= 0 {
				if .Pressed not_in object.state.previous {
					object.input.anchor = content_layout.mouse_index
					if object.click.count == 3 {
						tedit.editor_execute(&object.input.editor, .Select_All)
					} else {
						object.input.editor.selection = {
							content_layout.mouse_index,
							content_layout.mouse_index,
						}
					}
				}
				switch object.click.count {
				case 2:
					if content_layout.mouse_index < object.input.anchor {
						if content_string[content_layout.mouse_index] == ' ' {
							object.input.editor.selection[0] = content_layout.mouse_index
						} else {
							object.input.editor.selection[0] = max(
								0,
								strings.last_index_proc(
									content_string[:content_layout.mouse_index],
									is_separator,
								) +
								1,
							)
						}
						object.input.editor.selection[1] = strings.index_proc(
							content_string[object.input.anchor:],
							is_separator,
						)
						if object.input.editor.selection[1] == -1 {
							object.input.editor.selection[1] = len(content_string)
						} else {
							object.input.editor.selection[1] += object.input.anchor
						}
					} else {
						object.input.editor.selection[1] = max(
							0,
							strings.last_index_proc(
								content_string[:object.input.anchor],
								is_separator,
							) +
							1,
						)
						if (content_layout.mouse_index > 0 &&
							   content_string[content_layout.mouse_index - 1] == ' ') {
							object.input.editor.selection[0] = 0
						} else {
							object.input.editor.selection[0] = strings.index_proc(
								content_string[content_layout.mouse_index:],
								is_separator,
							)
						}
						if object.input.editor.selection[0] == -1 {
							object.input.editor.selection[0] =
								len(content_string) - content_layout.mouse_index
						}
						object.input.editor.selection[0] += content_layout.mouse_index
					}
				case 1:
					object.input.editor.selection[0] = content_layout.mouse_index
				}
			}
			if .Active in object.state.previous && len(content_layout.glyphs) > 0 {
				glyph := content_layout.glyphs[content_layout.glyph_selection[0]]
				glyph_pos := (text_origin - object.input.offset) + glyph.offset
				cursor_box := Box {
					glyph_pos + {0, -2},
					glyph_pos + {0, content_layout.font.line_height + 2},
				}
				inner_box := shrink_box(object.box, global_state.style.text_padding)
				object.input.offset.x += max(0, cursor_box.hi.x - inner_box.hi.x)
				if box_width(inner_box) > box_width(cursor_box) {
					object.input.offset.x -= max(0, inner_box.lo.x - cursor_box.lo.x)
				}
				if multiline {
					object.input.offset.y += max(0, cursor_box.hi.y - inner_box.hi.y)
					if box_height(inner_box) > box_height(cursor_box) {
						object.input.offset.y -= max(0, inner_box.lo.y - cursor_box.lo.y)
					}
				}
			} else {
				object.input.offset = {}
			}
			if last_selection != object.input.editor.selection {
				draw_frames(1)
			}
			if result.confirmed {
				object.state.current -= {.Active}
			}

			text_origin -= object.input.offset
			if object_is_visible(object) {
				vgo.fill_box(object.box, current_options().radius, paint = style.color.foreground)
				vgo.push_scissor(vgo.make_box(object.box, current_options().radius))
				if len(content_string) == 0 {
					vgo.fill_text(
						placeholder,
						text_size,
						text_origin,
						paint = vgo.fade(style.color.content, 0.5),
					)
				}
				if !vgo.text_layout_is_empty(&prefix_layout) {
					vgo.fill_text_layout(
						prefix_layout,
						text_origin + {-prefix_layout.size.x, 0},
						paint = vgo.fade(style.color.content, 0.5),
					)
				}
				if .Active in object.state.previous {
					draw_text_layout_highlight(
						content_layout,
						text_origin,
						vgo.fade(style.color.accent, 1.0 / 3.0),
					)
				}
				vgo.fill_text_layout(content_layout, text_origin, paint = style.color.content)
				if .Active in object.state.previous {
					draw_frames(1)
					draw_text_layout_cursor(
						content_layout,
						text_origin,
						vgo.fade(
							style.color.accent,
							clamp(0.5 + cast(f32)math.sin(time.duration_seconds(time.since(global_state.start_time)) * 7) * 1.5, 0, 1),
						),
					)
				}
				vgo.pop_scissor()
				vgo.stroke_box(
					object.box,
					1,
					radius = current_options().radius,
					paint = style.color.accent if .Active in object.state.current else style.color.button,
				)
			}
		}

		if .Changed in object.state.current {
			when T == string {
				delete(content^)
				content^ = strings.clone(strings.to_string(object.input.builder))
			} else when T == cstring {
				delete(content^)
				content^ = strings.clone_to_cstring(strings.to_string(object.input.builder))
			} else when intrinsics.type_is_numeric(T) {
				if parsed_value, ok := strconv.parse_f64(strings.to_string(object.input.builder));
				   ok {
					content^ = T(parsed_value)
				}
			}
			result.changed = true
		}

		end_object()
	}
	return
}

draw_text_layout_cursor :: proc(layout: vgo.Text_Layout, origin: [2]f32, color: vgo.Color) {
	if len(layout.glyphs) == 0 {
		return
	}
	line_height := layout.font.line_height * layout.font_scale
	cursor_origin := origin + layout.glyphs[layout.glyph_selection[0]].offset
	vgo.fill_box(
		snapped_box(
			{
				{cursor_origin.x - 1, cursor_origin.y},
				{cursor_origin.x + 1, cursor_origin.y + line_height},
			},
		),
		paint = color,
	)
}

draw_text_layout_highlight :: proc(layout: vgo.Text_Layout, origin: [2]f32, color: vgo.Color) {
	if layout.glyph_selection[0] == layout.glyph_selection[1] {
		return
	}
	line_height := layout.font.line_height * layout.font_scale
	for &line, i in layout.lines {
		to_ordered_range :: proc(range: [2]$T) -> [2]T {
			range := range
			if range.x > range.y {
				range = range.yx
			}
			return range
		}
		selection_range := to_ordered_range(layout.glyph_selection)
		highlight_range := [2]int {
			max(selection_range.x, line.glyph_range.x),
			min(selection_range.y, line.glyph_range.y),
		}
		if highlight_range.x <= highlight_range.y {
			box := Box {
				origin + layout.glyphs[highlight_range.x].offset,
				origin + layout.glyphs[highlight_range.y].offset + {0, line_height},
			}
			box.hi.x +=
				layout.font.space_advance *
				layout.font_scale *
				f32(i32(selection_range.y > line.glyph_range.y))
			vgo.fill_box(snapped_box(box), paint = color)
		}
	}
}
