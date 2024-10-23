package onyx

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

// Optional stickers for inputs
Input_Decal :: enum {
	None,
	Check,
	Spinner,
}

// The generic input widget takes a pointer to a `string.Builder` and edits it directly
Input_Info :: struct {
	using _:     Widget_Info,
	builder:     ^strings.Builder,
	placeholder: string,
	prefix:      string,
	decal:       Input_Decal,
	shake:       f32,
	monospace:   bool,
	multiline:   bool,
	read_only:   bool,
	hidden:      bool,
	undecorated: bool,
	text_info:   Text_Info,
	text_job:    Text_Job,
	text_pos:    [2]f32,
	changed:     bool,
	submitted:   bool,
	enter:       bool,
}

Input_State :: struct {
	editor:    tedit.Editor,
	builder:   strings.Builder,
	anchor:    int,
	icon_time: f32,
	offset:    [2]f32,
}

init_input :: proc(info: ^Input_Info, loc := #caller_location) -> bool {
	if info.id == 0 do info.id = hash(loc)
	info.self = get_widget(info.id) or_return
	// Flag as an input and to keep data
	info.self.flags += {.Is_Input, .Persistent}
	// Make sticky for easy highlighting
	info.sticky = true
	// Default desired size
	info.desired_size = core.style.visual_size
	//
	info.text_info = Text_Info {
		font   = core.style.monospace_font if info.monospace else core.style.default_font,
		size   = core.style.content_text_size,
		hidden = info.hidden && len(info.text_info.text) > 0,
	}
	// Stuff
	if info.builder != nil {
		info.text_info.text = strings.to_string(info.builder^)
	}
	return true
}

input_behavior :: proc(info: ^Input_Info) -> bool {
	assert(info != nil)
	assert(info.self != nil)
	//
	editor := &info.self.input.editor
	//
	if info.self.visible || .Active in info.self.state {
		info.text_job = make_text_job(
			info.text_info,
			editor,
			core.mouse_pos - (info.text_pos - info.self.input.offset),
		) or_return
	}
	//
	if editor.builder == nil {
		tedit.make_editor(editor, context.allocator, context.allocator)
		tedit.begin(editor, 0, info.builder)
		editor.set_clipboard = __set_clipboard_string
		editor.get_clipboard = __get_clipboard_string
	}
	// Animations
	info.self.focus_time = animate(info.self.focus_time, 0.15, .Active in info.self.state)
	info.self.input.icon_time = animate(info.self.input.icon_time, 0.2, info.decal != .None)
	// Hover cursor
	if .Hovered in info.self.state {
		core.cursor_type = .I_Beam
	}
	if .Active in info.self.state {
		if (core.focused_widget != core.last_focused_widget) && !key_down(.Left_Control) {
			info.self.state -= {.Active}
		}
	} else {
		if .Pressed in (info.self.state - info.self.last_state) {
			info.self.state += {.Active}
		}
	}
	// Deactivate if escape is pressed otherwise treat deactivation as submition
	if key_pressed(.Escape) {
		info.self.state -= {.Active}
	} else if .Active in (info.self.last_state - info.self.state) {
		info.submitted = true
	}
	// Do stuff
	if .Active in info.self.state {
		cmd: tedit.Command
		control_down := key_down(.Left_Control) || key_down(.Right_Control)
		shift_down := key_down(.Left_Shift) || key_down(.Right_Shift)
		// Control actions
		if control_down {
			if key_pressed(.A) do cmd = .Select_All
			if key_pressed(.C) do cmd = .Copy
			if key_pressed(.V) do cmd = .Paste
			if key_pressed(.X) do cmd = .Cut
			if key_pressed(.Z) do cmd = .Undo
			if key_pressed(.Y) do cmd = .Redo
		}
		// Write allowed and runes available?
		if !info.read_only && len(core.runes) > 0 {
			// Determine filter string
			allowed: string
			// if info.numeric {
			// 	allowed = "0123456789."
			// 	if info.integer || strings.contains_rune(strings.to_string(builder^), '.') {
			// 		allowed = allowed[:len(allowed) - 1]
			// 	}
			// }
			// Input filtered runes
			for char, c in core.runes {
				if len(allowed) > 0 && !strings.contains_rune(allowed, char) do continue
				tedit.input_runes(&info.self.input.editor, {char})
				info.changed = true
				core.draw_this_frame = true
			}
		}
		if key_pressed(.Backspace) do cmd = .Delete_Word_Left if control_down else .Backspace
		if key_pressed(.Delete) do cmd = .Delete_Word_Right if control_down else .Delete
		if key_pressed(.Enter) {
			cmd = .New_Line
			if info.multiline {
				if control_down {
					info.submitted = true
					info.enter = true
				}
			} else {
				info.submitted = true
				info.enter = true
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
		if !info.multiline && (cmd in tedit.MULTILINE_COMMANDS) {
			cmd = .None
		}
		if info.read_only && (cmd in tedit.EDIT_COMMANDS) {
			cmd = .None
		}
		if cmd != .None {
			tedit.editor_execute(&info.self.input.editor, cmd)
			info.changed = true
			core.draw_this_frame = true
		}
	}
	//
	word_proc :: proc(r: rune) -> bool {
		return !unicode.is_alpha(r) && !unicode.is_digit(r)
	}
	// Mouse selection
	last_selection := editor.selection
	// Input is currently pressed and hovered rune is valid
	if .Pressed in info.self.state && info.text_job.hovered_rune >= 0 {
		// Was just pressed?
		if .Pressed not_in info.self.last_state {
			// Set click anchor
			info.self.input.anchor = info.text_job.hovered_rune
			// Initial selection
			if info.self.click_count == 3 {
				// Triple-click selects all
				tedit.editor_execute(editor, .Select_All)
			} else {
				// Default case
				editor.selection = {info.text_job.hovered_rune, info.text_job.hovered_rune}
			}
		}
		// Handle dragging
		switch info.self.click_count {
		// Double-click selects by `word_proc`
		case 2:
			if info.text_job.hovered_rune < info.self.input.anchor {
			if info.text_info.text[info.text_job.hovered_rune] == ' ' {
			editor.selection[0] = info.text_job.hovered_rune
				} else {
					editor.selection[0] = max(
						0,
						strings.last_index_proc(
							info.text_info.text[:info.text_job.hovered_rune],
							word_proc,
						) +
						1,
					)
				}
				editor.selection[1] = strings.index_proc(
					info.text_info.text[info.self.input.anchor:],
					word_proc,
				)
				if editor.selection[1] == -1 {
					editor.selection[1] = len(info.text_info.text)
				} else {
					editor.selection[1] += info.self.input.anchor
				}
			} else {
				editor.selection[1] = max(
					0,
					strings.last_index_proc(info.text_info.text[:info.self.input.anchor], word_proc) +
					1,
				)
				if (info.text_job.hovered_rune > 0 &&
					   info.text_info.text[info.text_job.hovered_rune - 1] == ' ') {
					editor.selection[0] = 0
				} else {
					editor.selection[0] = strings.index_proc(
						info.text_info.text[info.text_job.hovered_rune:],
						word_proc,
					)
				}
				if editor.selection[0] == -1 {
					editor.selection[0] = len(info.text_info.text) - info.text_job.hovered_rune
				}
				editor.selection[0] += info.text_job.hovered_rune
			}
		// Normal select
		case 1:
			editor.selection[0] = info.text_job.hovered_rune
		}
	}
	// Resolve view offset so the cursor is always shown
	if .Active in info.self.last_state && info.text_job.cursor_glyph >= 0 {
		glyph := info.text_job.glyphs[info.text_job.cursor_glyph]
		glyph_pos := (info.text_pos - info.self.input.offset) + glyph.pos
		// The cursor's own bounding box
		cursor_box := Box{glyph_pos + {-1, -2}, glyph_pos + {1, info.text_job.line_height + 2}}
		// The box we want the cursor to stay in
		inner_box := shrink_box(info.self.box, 4)
		// Move view offset
		info.self.input.offset.x += max(0, cursor_box.hi.x - inner_box.hi.x)
		if box_width(inner_box) > box_width(cursor_box) {
			info.self.input.offset.x -= max(0, inner_box.lo.x - cursor_box.lo.x)
		}
		if info.multiline {
			info.self.input.offset.y += max(0, cursor_box.hi.y - inner_box.hi.y)
			if box_height(inner_box) > box_height(cursor_box) {
				info.self.input.offset.y -= max(0, inner_box.lo.y - cursor_box.lo.y)
			}
		}
	} else {
		info.self.input.offset = {}
	}
	// Draw the next frame if a new selection was made
	if last_selection != editor.selection {
		core.draw_next_frame = true
	}
	// Deactivate when submitted
	if info.submitted {
		info.self.state -= {.Active}
	}
	return true
}

add_input :: proc(using info: ^Input_Info) -> bool {
	using tedit

	begin_widget(info) or_return
	defer end_widget()

	if info.shake > 0 {
		core.draw_next_frame = true
		self.box = move_box(
			self.box,
			{
				info.shake *
				cast(f32)math.sin(time.duration_seconds(time.since(core.start_time)) * 50) *
				5,
				0,
			},
		)
	}

	if self.visible && !undecorated {
		draw_rounded_box_fill(self.box, core.style.rounding, core.style.color.background)
	}

	if builder == nil {
		return false
	}

	text_pos = self.box.lo - self.input.offset

	if .Active in self.state || submitted {
		text_info.text = strings.to_string(builder^)
	}

	// Offset text origin based on font size
	info.text_pos.x += core.style.text_padding.x
	if font, ok := &core.fonts[text_info.font].?; ok {
		if font_size, ok := get_font_size(font, text_info.size); ok {
			if info.multiline {
				text_pos.y = self.box.lo.y + (font_size.ascent - font_size.descent) / 2
			} else {
				text_pos.y =
					(self.box.hi.y + self.box.lo.y) / 2 -
					(font_size.ascent - font_size.descent) / 2
			}
		}
	}
	// `text_offset` must be updated for the mouse interaction to line up
	prefix_text_job: Maybe(Text_Job)
	if len(prefix) > 0 {
		prefix_text_job, _ = make_text_job({text = prefix, options = text_info.options})
		if prefix_text_job, ok := prefix_text_job.?; ok {
			text_pos.x += prefix_text_job.size.x
		}
	}

	input_behavior(info) or_return

	// Hover
	if point_in_box(core.mouse_pos, self.box) {
		hover_widget(self)
	}

	if self.visible {
		push_scissor(self.box, add_shape_box(self.box, core.style.rounding))
		// Draw text placeholder
		if len(text_info.text) == 0 {
			text_info := text_info
			text_info.text = info.placeholder
			draw_text(text_pos, text_info, fade(core.style.color.content, 0.5))
		}
		// Draw prefix
		if prefix_text_job, ok := prefix_text_job.?; ok {
			draw_text_glyphs(
				prefix_text_job,
				text_pos + {-prefix_text_job.size.x, 0},
				fade(core.style.color.content, 0.5),
			)
		}
		// First draw the highlighting behind the text
		if .Active in self.last_state {
			draw_text_highlight(text_job, text_pos, fade(core.style.color.accent, 0.5))
		}
		// Then draw the text
		draw_text_glyphs(text_job, text_pos, core.style.color.content)
		// Draw the cursor in front of the text
		if .Active in self.last_state {
			draw_text_cursor(text_job, text_pos, core.style.color.accent)
		}
		pop_scissor()
		// Draw decal
		if self.input.icon_time > 0 {
			a := box_height(self.box) / 2
			center := [2]f32{self.box.hi.x, self.box.lo.y} + [2]f32{-a, a}
			switch decal {
			case .None:
				break
			case .Check:
				scale := [2]f32{1 + 4 * self.input.icon_time, 5}
				// begin_path()
				// point(center + {-1, -0.047} * scale)
				// point(center + {-0.333, 0.619} * scale)
				// point(center + {1, -0.713} * scale)
				// stroke_path(2, {0, 255, 120, 255})
				// end_path()
			case .Spinner:
				draw_spinner(center, 5, core.style.color.content)
			}
		}
		// Optional outline
		if !undecorated {
			draw_rounded_box_stroke(
				self.box,
				core.style.rounding,
				2,
				fade(core.style.color.accent, self.focus_time),
			)
		}
		// Draw disabled overlay
		if self.disable_time > 0 {
			draw_rounded_box_fill(
				self.box,
				core.style.rounding,
				fade(core.style.color.foreground, self.disable_time * 0.5),
			)
		}
	}

	return true
}

input :: proc(info: Input_Info, loc := #caller_location) -> Input_Info {
	info := info
	if info.builder != nil && init_input(&info, loc) {
		add_input(&info)
	}
	return info
}

// A wrapper for the generic input that directly edits a string
String_Input_Info :: struct {
	using _: Input_Info,
	value:   ^string,
}

init_string_input :: proc(using info: ^String_Input_Info, loc := #caller_location) -> bool {
	if value == nil {
		return false
	}
	init_input(info, loc) or_return
	if builder == nil {
		builder = &self.input.builder
	}
	if .Active in (self.state - self.last_state) {
		strings.builder_reset(builder)
		strings.write_string(builder, value^)
	}
	text_info.text = value^
	return true
}

add_string_input :: proc(using info: ^String_Input_Info) -> bool {
	add_input(info) or_return
	if submitted {
		delete(value^)
		value^ = strings.clone(strings.to_string(builder^))
	}
	return true
}

string_input :: proc(info: String_Input_Info, loc := #caller_location) -> Input_Info {
	info := info
	if init_string_input(&info, loc) {
		add_string_input(&info)
	}
	return info
}

Number_Input_Info :: struct($T: typeid) where intrinsics.type_is_numeric(T) {
	using _:   Input_Info,
	value:     ^T,
	lo, hi:    T,
	increment: Maybe(T),
	format:    Maybe(string),
}

init_number_input :: proc(info: ^Number_Input_Info($T), loc := #caller_location) -> bool {
	if info.value == nil {
		return false
	}
	init_input(info, loc) or_return
	info.builder = &info.self.input.builder
	// Was this input just activated?
	if .Active in (info.self.state - info.self.last_state) {
		strings.builder_reset(info.builder)
		fmt.sbprintf(info.builder, info.format.? or_else "{:v}", info.value^)
	}
	if .Active not_in info.self.state {
		info.text_info.text = fmt.tprintf(info.format.? or_else "{:v}", info.value^)
	}
	return true
}

add_number_input :: proc(using info: ^Number_Input_Info($T)) -> bool {
	add_input(info) or_return
	if submitted {
		switch typeid_of(T) {
		case u64:
			value^ = strconv.parse_u64(strings.to_string(builder^)) or_return
		}
	}
	return true
}

number_input :: proc(
	info: Number_Input_Info($T),
	loc := #caller_location,
) -> Number_Input_Info(T) {
	info := info
	if init_number_input(&info, loc) {
		add_number_input(&info)
	}
	return info
}
