package onyx

import "../vgo"
import "base:intrinsics"
import "base:runtime"
import "core:fmt"
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

Input :: struct {
	editor:      tedit.Editor,
	builder:     strings.Builder,
	anchor:      int,
	active_time: f32,
	offset:      [2]f32,
}

destroy_input :: proc(input: ^Input) {
	tedit.destroy_editor(&input.editor)
	strings.builder_destroy(&input.builder)
}

raw_input :: proc(
	content: ^string,
	placeholder: string = "",
	prefix: string = "",
	obfuscate: bool = false,
	decal: Input_Decal = .None,
	is_multiline: bool = false,
	is_monospace: bool = false,
	loc := #caller_location,
) {
	if content == nil {
		return
	}
	object := persistent_object(hash(loc))
	if object.variant == nil {
		input := Input {
			builder = strings.builder_make(),
		}
		strings.write_string(&input.builder, content^)
		object.variant = input
	}

	extras := &object.variant.(Input)
	if begin_object(object) {

		object.box = next_box({})

		handle_object_click(object, true)

		is_visible := object_is_visible(object)

		box := object.box
		text_size := global_state.style.content_text_size
		content_text :=
			strings.to_string(extras.builder) if .Active in object.state.current else content^
		colors := style().color
		state := object.state

		rounding := current_options().radius

		if is_visible {
			vgo.fill_box(box, radius = rounding, paint = style().color.field)
		}

		font :=
			(global_state.style.monospace_font if (is_monospace) else global_state.style.default_font)
		text_origin: [2]f32
		if is_multiline {
			text_origin = box.lo + global_state.style.text_padding + {0, 2}
		} else {
			text_origin = {
				box.lo.x + global_state.style.text_padding.x,
				box_center_y(box) - font.line_height * text_size * 0.5,
			}
		}
		submitted := !(!key_down(.Left_Control) && is_multiline) && key_pressed(.Enter)
		editor := &extras.editor
		content_layout: vgo.Text_Layout

		vgo.set_font(font)

		prefix_layout: vgo.Text_Layout
		if len(prefix) > 0 {
			prefix_layout = vgo.make_text_layout(prefix, text_size)
			text_origin.x += prefix_layout.size.x
		}

		if is_visible || .Active in object.state.current {
			content_layout = vgo.make_text_layout(
				content_text,
				text_size,
				selection = editor.selection,
				local_mouse = mouse_point() - (text_origin - extras.offset),
			)
		}
		//
		if editor.builder == nil {
			tedit.make_editor(editor, context.allocator, context.allocator)
			tedit.begin(editor, 0, &extras.builder)
			editor.set_clipboard = __set_clipboard_string
			editor.get_clipboard = __get_clipboard_string
		}
		extras.active_time = animate(extras.active_time, 0.15, .Active in object.state.current)
		if .Hovered in object.state.current {
			set_cursor(.I_Beam)
		}
		if .Active in object.state.current {
			if user_focus_just_changed() && !key_down(.Left_Control) {
				object.state.current -= {.Active}
			}
		} else {
			if .Pressed in new_state(object.state) {
				object.state.current += {.Active}
			}
		}
		if key_pressed(.Escape) {
			object.state.current -= {.Active}
		} else if .Active in lost_state(object.state) {
			submitted = true
		}
		if .Active in object.state.current {
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
					tedit.input_runes(&extras.editor, {char})
					draw_frames(1)
					object.state.current += {.Changed}
				}
			}
			if key_pressed(.Backspace) do cmd = .Delete_Word_Left if control_down else .Backspace
			if key_pressed(.Delete) do cmd = .Delete_Word_Right if control_down else .Delete
			if key_pressed(.Enter) {
				cmd = .New_Line
				if is_multiline {
					if control_down {
						submitted = true
					}
				} else {
					submitted = true
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
			if !is_multiline && (cmd in tedit.MULTILINE_COMMANDS) {
				cmd = .None
			}
			if cmd != .None {
				tedit.editor_execute(&extras.editor, cmd)
				object.state.current += {.Changed}
				draw_frames(1)
			}
		}

		is_separator :: proc(r: rune) -> bool {
			return !unicode.is_alpha(r)
		}

		last_selection := editor.selection
		if .Pressed in object.state.current && content_layout.mouse_index >= 0 {
			if .Pressed not_in object.state.previous {
				extras.anchor = content_layout.mouse_index
				if object.input.click_count == 3 {
					tedit.editor_execute(editor, .Select_All)
				} else {
					editor.selection = {content_layout.mouse_index, content_layout.mouse_index}
				}
			}
			switch object.input.click_count {
			case 2:
				if content_layout.mouse_index < extras.anchor {
					if content_text[content_layout.mouse_index] == ' ' {
						editor.selection[0] = content_layout.mouse_index
					} else {
						editor.selection[0] = max(
							0,
							strings.last_index_proc(
								content_text[:content_layout.mouse_index],
								is_separator,
							) +
							1,
						)
					}
					editor.selection[1] = strings.index_proc(
						content_text[extras.anchor:],
						is_separator,
					)
					if editor.selection[1] == -1 {
						editor.selection[1] = len(content_text)
					} else {
						editor.selection[1] += extras.anchor
					}
				} else {
					editor.selection[1] = max(
						0,
						strings.last_index_proc(content_text[:extras.anchor], is_separator) + 1,
					)
					if (content_layout.mouse_index > 0 &&
						   content_text[content_layout.mouse_index - 1] == ' ') {
						editor.selection[0] = 0
					} else {
						editor.selection[0] = strings.index_proc(
							content_text[content_layout.mouse_index:],
							is_separator,
						)
					}
					if editor.selection[0] == -1 {
						editor.selection[0] = len(content_text) - content_layout.mouse_index
					}
					editor.selection[0] += content_layout.mouse_index
				}
			case 1:
				editor.selection[0] = content_layout.mouse_index
			}
		}
		if .Active in object.state.previous && len(content_layout.glyphs) > 0 {
			glyph := content_layout.glyphs[content_layout.glyph_selection[0]]
			glyph_pos := (text_origin - extras.offset) + glyph.offset
			cursor_box := Box {
				glyph_pos + {0, -2},
				glyph_pos + {0, content_layout.font.line_height + 2},
			}
			inner_box := shrink_box(object.box, global_state.style.text_padding)
			extras.offset.x += max(0, cursor_box.hi.x - inner_box.hi.x)
			if box_width(inner_box) > box_width(cursor_box) {
				extras.offset.x -= max(0, inner_box.lo.x - cursor_box.lo.x)
			}
			if is_multiline {
				extras.offset.y += max(0, cursor_box.hi.y - inner_box.hi.y)
				if box_height(inner_box) > box_height(cursor_box) {
					extras.offset.y -= max(0, inner_box.lo.y - cursor_box.lo.y)
				}
			}
		} else {
			extras.offset = {}
		}
		if last_selection != editor.selection {
			draw_frames(1)
		}
		if submitted {
			object.state.current -= {.Active}
		}

		text_origin -= extras.offset

		if point_in_box(mouse_point(), object.box) {
			hover_object(object)
		}

		if is_visible {
			vgo.push_scissor(vgo.make_box(object.box, global_state.style.rounding))
			if len(content_text) == 0 {
				vgo.fill_text(
					placeholder,
					text_size,
					text_origin,
					paint = vgo.fade(style().color.content, 0.5),
				)
			}
			if len(prefix) > 0 {
				vgo.fill_text_layout(
					prefix_layout,
					text_origin + {-prefix_layout.size.x, 0},
					paint = vgo.fade(style().color.content, 0.5),
				)
			}
			line_height := font.line_height * text_size
			if .Active in object.state.previous {
				if content_layout.glyph_selection[0] != content_layout.glyph_selection[1] {
					for &line in content_layout.lines {
						range := [2]int {
							max(content_layout.glyph_selection[0], line.glyph_range[0]),
							min(content_layout.glyph_selection[1], line.glyph_range[1]),
						}
						if range[0] != range[1] {
							range = {min(range[0], range[1]), max(range[0], range[1])}
							vgo.fill_box(
								{
									text_origin + content_layout.glyphs[range[0]].offset,
									text_origin +
									content_layout.glyphs[range[1]].offset +
									{0, line_height},
								},
								paint = vgo.fade(style().color.accent, 0.5),
							)
						}
					}
				}
			}
			vgo.fill_text_layout(content_layout, text_origin, paint = style().color.content)
			if .Active in object.state.previous && len(content_layout.glyphs) > 0 {
				cursor_origin :=
					text_origin + content_layout.glyphs[content_layout.glyph_selection[0]].offset
				vgo.fill_box(
					{
						{cursor_origin.x - 1, cursor_origin.y - 2},
						{cursor_origin.x + 1, cursor_origin.y + line_height + 2},
					},
					paint = style().color.accent,
				)
			}
			vgo.pop_scissor()

			if decal != .None {
				a := box_height(object.box) / 2
				center := [2]f32{object.box.hi.x, object.box.lo.y} + [2]f32{-a, a}
				switch decal {
				case .None:
					break
				case .Check:
					vgo.check(center, 7, vgo.GREEN)
				case .Spinner:
					vgo.spinner(center, 7, style().color.content)
					draw_frames(1)
				}
			}

			vgo.stroke_box(
				object.box,
				2,
				radius = rounding,
				paint = vgo.fade(style().color.accent, extras.active_time),
				// outline = .Outer_Stroke,
			)
		}

		if .Changed in object.state.current {
			delete(content^)
			content^ = strings.clone(strings.to_string(extras.builder))
		}

		end_object()
	}
	return
}
