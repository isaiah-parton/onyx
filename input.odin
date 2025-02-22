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
import "core:reflect"
import "core:strconv"
import "core:strings"
import "core:time"
import "core:unicode"
import "core:unicode/utf8"
import "tedit"

Input_Decal :: enum {
	None,
	Check,
	Spinner,
}

Input_State :: struct {
	editor:           tedit.Editor,
	builder:          strings.Builder,
	anchor:           int,
	offset:           [2]f32,
	last_mouse_index: int,
	action_time:      time.Time,
	match_list: [dynamic]string,
	closest_match: string,
}

input_select_all :: proc(object: ^Object) {
	object.input.editor.selection = {len(object.input.builder.buf), 0}
}

destroy_input :: proc(input: ^Input_State) {
	delete(input.match_list)
	tedit.destroy_editor(&input.editor)
	strings.builder_destroy(&input.builder)
	input^ = {}
}

activate_input :: proc(object: ^Object) {
	object.state.current += {.Active}
}

Input_Result :: struct {
	confirmed: bool,
	changed:   bool,
	is_empty:  bool,
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

input :: proc(
	value: any,
	format: string = "%v",
	prefix: string = "",
	placeholder: string = "",
	flags: Input_Flags = {},
	loc := #caller_location,
) -> Input_Result {
	type_info := runtime.type_info_base(type_info_of(value.id))
	if pointer_info, ok := type_info.variant.(runtime.Type_Info_Pointer); ok {
		return raw_input(
			(^rawptr)(value.data)^,
			pointer_info.elem,
			format,
			prefix,
			placeholder,
			flags,
			loc,
		)
	}
	return raw_input(value.data, type_info, format, prefix, placeholder, flags, loc)
}

raw_input :: proc(
	data: rawptr,
	type_info: ^runtime.Type_Info,
	format: string = "%v",
	prefix: string = "",
	placeholder: string = "",
	flags: Input_Flags = {},
	loc := #caller_location,
) -> (
	result: Input_Result,
) {
	if data == nil || type_info == nil {
		return {}
	}
	type_info := runtime.type_info_base(type_info)

	object := get_object(hash(loc))
	if .Is_Input not_in object.flags {
		object.flags += {.Is_Input, .Sticky_Press, .Sticky_Hover}
		object.input.builder = strings.builder_make()
	}
	object.size = style().visual_size
	object.box = next_box(object.size)

	if begin_object(object) {

		content_string: string
		if .Active not_in object.state.current {
			strings.builder_reset(&object.input.builder)
			fmt.sbprintf(&object.input.builder, format, any{id = type_info.id, data = data})
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

			if .Pressed not_in object.state.current &&
			   object.input.last_mouse_index != content_layout.mouse_index {
				object.click.count = 0
			}
			object.input.last_mouse_index = content_layout.mouse_index

			if .Active in object.state.current {
				if .Active not_in object.state.previous {
					strings.builder_reset(&object.input.builder)
					fmt.sbprintf(
						&object.input.builder,
						format,
						any{id = type_info.id, data = data},
					)
					if .Select_All in flags {
						tedit.editor_execute(&object.input.editor, .Select_All)
					}
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
						if len(object.input.closest_match) > 0 {
							strings.builder_reset(&object.input.builder)
							strings.write_string(&object.input.builder, object.input.closest_match)
							object.state.current += {.Changed}
						}
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

			last_selection := object.input.editor.selection

			text_mouse_selection(object, content_string, &content_layout)

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
				vgo.fill_box(object.box, current_options().radius, paint = style.color.field)
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
					if len(object.input.closest_match) > 0 {
						text_layout := vgo.make_text_layout(object.input.closest_match, text_size)
						vgo.fill_text_layout_range(text_layout, {len(content_layout.glyphs) - 1, len(text_layout.glyphs)}, text_origin, paint = vgo.fade(style.color.content, 0.5))
					}
				}
				vgo.fill_text_layout(content_layout, text_origin, paint = style.color.content)
				if .Active in object.state.previous {
					draw_frames(1)
					draw_text_layout_cursor(
						content_layout,
						text_origin,
						vgo.fade(
							style.color.accent,
							clamp(
								0.5 +
								cast(f32)math.sin(
										time.duration_seconds(
											time.since(global_state.start_time),
										) *
										7,
									) *
									1.5,
								0,
								1,
							),
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
			if enum_info, ok := type_info.variant.(runtime.Type_Info_Enum); ok {
				most_matching_runes: int
				clear(&object.input.match_list)
				for name, i in enum_info.names {
					matching_runes := fuzzy_match(strings.to_string(object.input.builder), name)
					if matching_runes > most_matching_runes {
						most_matching_runes = matching_runes
						inject_at(&object.input.match_list, 0, name)
					} else if matching_runes > 0 {
						append(&object.input.match_list, name)
					}
				}
				object.input.closest_match = ""
				most_matching_runes = 0
				for name, i in enum_info.names {
					matching_runes := match_start(strings.to_string(object.input.builder), name)
					if matching_runes > most_matching_runes {
						most_matching_runes = matching_runes
						object.input.closest_match = name
					}
				}
			}
			result.changed = replace_input_content(data, type_info, strings.to_string(object.input.builder))
		}

		end_object()
	}
	return
}

replace_input_content :: proc(
	data: rawptr,
	type_info: ^runtime.Type_Info,
	text: string,
	allocator := context.allocator,
) -> bool {
	#partial switch v in type_info.variant {
	case (runtime.Type_Info_String):
		if v.is_cstring {
			cstring_pointer := (^cstring)(data)
			delete(cstring_pointer^)
			cstring_pointer^ = strings.clone_to_cstring(text, allocator = allocator)
		} else {
			string_pointer := (^string)(data)
			delete(string_pointer^)
			string_pointer^ = strings.clone(text, allocator = allocator)
		}
	case (runtime.Type_Info_Float):
		switch type_info.id {
		case f16:
			(^f16)(data)^ = cast(f16)strconv.parse_f32(text) or_return
		case f32:
			(^f32)(data)^ = strconv.parse_f32(text) or_return
		case f64:
			(^f64)(data)^ = strconv.parse_f64(text) or_return
		}
	case (runtime.Type_Info_Integer):
		switch type_info.id {
		case int:
			(^int)(data)^ = strconv.parse_int(text) or_return
		case i8:
			(^i8)(data)^ = cast(i8)strconv.parse_i64(text) or_return
		case i16:
			(^i16)(data)^ = cast(i16)strconv.parse_i64(text) or_return
		case i32:
			(^i32)(data)^ = cast(i32)strconv.parse_i64(text) or_return
		case i64:
			(^i64)(data)^ = strconv.parse_i64(text) or_return
		case i128:
			(^i128)(data)^ = strconv.parse_i128(text) or_return
		case uint:
			(^uint)(data)^ = strconv.parse_uint(text) or_return
		case u8:
			(^u8)(data)^ = cast(u8)strconv.parse_u64(text) or_return
		case u16:
			(^u16)(data)^ = cast(u16)strconv.parse_u64(text) or_return
		case u32:
			(^u32)(data)^ = cast(u32)strconv.parse_u64(text) or_return
		case u64:
			(^u64)(data)^ = strconv.parse_u64(text) or_return
		case u128:
			(^u128)(data)^ = strconv.parse_u128(text) or_return
		case:
			return false
		}
	case (runtime.Type_Info_Enum):
		for name, i in v.names {
			if text == name {
				mem.copy(data, &v.values[i], v.base.size)
				break
			}
		}
	case:
		break
	}
	return true
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
