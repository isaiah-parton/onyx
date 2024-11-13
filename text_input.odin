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
	using object: ^Object,
	editor:       tedit.Editor,
	builder:      strings.Builder,
	content:      string,
	prefix:       string,
	placeholder:  string,
	is_multiline: bool,
	is_monospace: bool,
	decal:        Input_Decal,
	anchor:       int,
	active_time:  f32,
	offset:       [2]f32,
}

raw_input :: proc(
	content: string,
	placeholder: string = "",
	prefix: string = "",
	obfuscate: bool = false,
	decal: Input_Decal = .None,
	multiline: bool = false,
	monospace: bool = false,
	loc := #caller_location,
) {
	object := persistent_object(hash(loc))
	if begin_object(object) {
		defer end_object()

		if object.variant == nil {
			object.variant = Input {
				object = object,
			}
		}

		input := &object.variant.(Input)
		input.desired_size = global_state.style.visual_size
		if .Active in input.state {
			input.content = strings.to_string(input.builder)
		} else {
			input.content = content
		}
	}
}

input_text_origin_from :: proc(box: Box, multiline: bool = false) -> [2]f32 {
	if multiline {
		return box.lo + global_state.style.text_padding
	}
	return {box.lo.x + global_state.style.text_padding.x, box_center_y(box)}
}

display_input :: proc(input: ^Input) {

	handle_object_click(input, true)

	is_visible := object_is_visible(input)

	box := input.box
	text_size := global_state.style.content_text_size
	colors := colors()
	state := input.state

	if is_visible {
		vgo.fill_box(box, global_state.style.rounding, colors.field)
	}

	text_origin := input_text_origin_from(box, input.is_multiline)
	submitted := !(!key_down(.Left_Control) && input.is_multiline) && key_pressed(.Enter)
	editor := &input.editor
	content_layout: vgo.Text_Layout

	font := (global_state.style.monospace_font if input.is_monospace else global_state.style.default_font)
	vgo.set_font(
		font,
	)

	prefix_layout: vgo.Text_Layout
	if len(input.prefix) > 0 {
		prefix_layout = vgo.make_text_layout(input.prefix, text_size)
		text_origin.x += prefix_layout.size.x
	}

	if is_visible || .Active in input.state {
		content_layout = vgo.make_text_layout(
			input.content,
			text_size,
			selection = editor.selection,
			local_mouse = mouse_point() - (text_origin - input.offset),
		)
	}
	//
	if editor.builder == nil {
		tedit.make_editor(editor, context.allocator, context.allocator)
		tedit.begin(editor, 0, &input.builder)
		editor.set_clipboard = __set_clipboard_string
		editor.get_clipboard = __get_clipboard_string
	}
	// Animations
	input.active_time = animate(input.active_time, 0.15, .Active in input.state)
	// Hover cursor
	if .Hovered in input.state {
		set_cursor(.I_Beam)
	}
	if .Active in input.state {
		if user_focus_just_changed() && !key_down(.Left_Control) {
			input.state -= {.Active}
		}
	} else {
		if .Pressed in (input.state - input.last_state) {
			input.state += {.Active}
		}
	}
	if key_pressed(.Escape) {
		input.state -= {.Active}
	} else if .Active in (input.last_state - input.state) {
		submitted = true
	}
	if .Active in input.state {
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
				tedit.input_runes(&input.editor, {char})
				draw_frames(1)
			}
		}
		if key_pressed(.Backspace) do cmd = .Delete_Word_Left if control_down else .Backspace
		if key_pressed(.Delete) do cmd = .Delete_Word_Right if control_down else .Delete
		if key_pressed(.Enter) {
			cmd = .New_Line
			if input.is_multiline {
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
		if !input.is_multiline && (cmd in tedit.MULTILINE_COMMANDS) {
			cmd = .None
		}
		if cmd != .None {
			tedit.editor_execute(&input.editor, cmd)
			input.state += {.Changed}
			draw_frames(1)
		}
	}

	is_separator :: proc(r: rune) -> bool {
		return !unicode.is_alpha(r)
	}

	last_selection := editor.selection
	if .Pressed in input.state && content_layout.mouse_index >= 0 {
		if .Pressed not_in input.last_state {
			input.anchor = content_layout.mouse_index
			if input.click_count == 3 {
				tedit.editor_execute(editor, .Select_All)
			} else {
				editor.selection = {content_layout.mouse_index, content_layout.mouse_index}
			}
		}
		switch input.click_count {
		case 2:
			if content_layout.mouse_index < input.anchor {
				if input.content[content_layout.mouse_index] == ' ' {
					editor.selection[0] = content_layout.mouse_index
				} else {
					editor.selection[0] = max(
						0,
						strings.last_index_proc(
							input.content[:content_layout.mouse_index],
							is_separator,
						) +
						1,
					)
				}
				editor.selection[1] = strings.index_proc(
					input.content[input.anchor:],
					is_separator,
				)
				if editor.selection[1] == -1 {
					editor.selection[1] = len(input.content)
				} else {
					editor.selection[1] += input.anchor
				}
			} else {
				editor.selection[1] = max(
					0,
					strings.last_index_proc(input.content[:input.anchor], is_separator) + 1,
				)
				if (content_layout.mouse_index > 0 &&
					   input.content[content_layout.mouse_index - 1] == ' ') {
					editor.selection[0] = 0
				} else {
					editor.selection[0] = strings.index_proc(
						input.content[content_layout.mouse_index:],
						is_separator,
					)
				}
				if editor.selection[0] == -1 {
					editor.selection[0] = len(input.content) - content_layout.mouse_index
				}
				editor.selection[0] += content_layout.mouse_index
			}
		case 1:
			editor.selection[0] = content_layout.mouse_index
		}
	}
	if .Active in input.last_state && len(content_layout.glyphs) > 0 {
		glyph := content_layout.glyphs[content_layout.glyph_selection[0]]
		glyph_pos := (text_origin - input.offset) + glyph.offset
		cursor_box := Box {
			glyph_pos + {-1, -2},
			glyph_pos + {1, content_layout.font.line_height + 2},
		}
		inner_box := shrink_box(input.box, 4)
		input.offset.x += max(0, cursor_box.hi.x - inner_box.hi.x)
		if box_width(inner_box) > box_width(cursor_box) {
			input.offset.x -= max(0, inner_box.lo.x - cursor_box.lo.x)
		}
		if input.is_multiline {
			input.offset.y += max(0, cursor_box.hi.y - inner_box.hi.y)
			if box_height(inner_box) > box_height(cursor_box) {
				input.offset.y -= max(0, inner_box.lo.y - cursor_box.lo.y)
			}
		}
	} else {
		input.offset = {}
	}
	if last_selection != editor.selection {
		draw_frames(1)
	}
	if submitted {
		input.state -= {.Active}
	}

	text_origin -= input.offset

	if point_in_box(mouse_point(), input.box) {
		hover_object(input)
	}

	if is_visible {
		vgo.push_scissor(vgo.make_box(input.box, global_state.style.rounding))
		if len(input.content) == 0 {
			vgo.fill_text(
				input.placeholder,
				text_size,
				text_origin,
				align_x = .Left,
				align_y = .Top if input.is_multiline else .Center,
				paint = vgo.fade(colors.content, 0.5),
			)
		}
		if len(input.prefix) > 0 {
			vgo.fill_text_layout(
				prefix_layout,
				text_origin + {-prefix_layout.size.x, 0},
				paint = vgo.fade(colors.content, 0.5),
			)
		}
		line_height := font.line_height * text_size
		if .Active in input.last_state {
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
								text_origin +
								content_layout.glyphs[range[0]].offset +
								{0, line_height * -0.5},
								text_origin +
								content_layout.glyphs[range[1]].offset +
								{0, line_height * 0.5},
							},
							paint = vgo.fade(colors.accent, 0.5),
						)
					}
				}
			}
		}
		vgo.fill_text_layout(
			content_layout,
			text_origin,
			.Left,
			.Top if input.is_multiline else .Center,
			colors.content,
		)
		if .Active in input.last_state && len(content_layout.glyphs) > 0 {
			cursor_origin :=
				text_origin + content_layout.glyphs[content_layout.glyph_selection[0]].offset
			vgo.fill_box(
				{
					{cursor_origin.x - 1, cursor_origin.y - line_height / 2},
					{cursor_origin.x + 1, cursor_origin.y + line_height / 2},
				},
				paint = colors.accent,
			)
		}
		vgo.pop_scissor()

		if input.decal != .None {
			a := box_height(input.box) / 2
			center := [2]f32{input.box.hi.x, input.box.lo.y} + [2]f32{-a, a}
			switch input.decal {
			case .None:
				break
			case .Check:
				vgo.check(center, 5, vgo.GREEN)
			case .Spinner:
				vgo.spinner(center, 5, colors.content)
			}
		}

		vgo.stroke_box(
			input.box,
			2 * input.active_time,
			global_state.style.rounding,
			paint = vgo.fade(colors.accent, input.active_time),
		)
	}
}
