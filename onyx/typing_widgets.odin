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

import "tedit"

Input_Decal :: enum {
	None,
	Check,
	Loader,
}

Input_Info :: struct {
	using _:     Widget_Info,
	builder:     ^strings.Builder,
	text:        string,
	monospace:   bool,
	placeholder: string,
	shake:       f32,
	multiline:   bool,
	read_only:   bool,
	hidden:      bool,
	decal:       Input_Decal,
	undecorated: bool,
	changed:     bool,
	submitted:   bool,
	enter:       bool,
}

Input_Widget_Kind :: struct {
	editor:    tedit.Editor,
	builder:   strings.Builder,
	anchor:    int,
	icon_time: f32,
	offset:    [2]f32,
}

String_Input_Info :: struct {
	using _: Input_Info,
	value:   ^string,
}

init_input :: proc(using info: ^Input_Info, loc := #caller_location) -> bool {
	id = hash(loc)
	self = get_widget(id) or_return
	sticky = true
	desired_size = core.style.visual_size
	if builder != nil {
		text = strings.to_string(builder^)
	}
	if .Active in self.state {
		if (core.focused_widget != core.last_focused_widget) && !key_down(.Left_Control) {
			self.state -= {.Active}
		}
	} else {
		if .Pressed in (self.state - self.last_state) {
			self.state += {.Active}
		}
	}
	// Deactivate if escape is pressed otherwise treat deactivation as submition
	if key_pressed(.Escape) {
		self.state -= {.Active}
	} else if .Active in (self.last_state - self.state) {
		submitted = true
	}
	return true
}

add_input :: proc(using info: ^Input_Info) -> bool {
	using tedit

	begin_widget(info) or_return
	defer end_widget()

	if info.shake > 0 {
		core.draw_next_frame = true
	}
	self.box = move_box(
		self.box,
		{
			info.shake *
			cast(f32)math.sin(time.duration_seconds(time.since(core.start_time)) * 50) *
			5,
			0,
		},
	)

	if self.visible && !undecorated {
		draw_rounded_box_fill(self.box, core.style.rounding, core.style.color.background)
	}

	if builder == nil {
		return false
	}

	// Cleanup procedure
	self.on_death = proc(self: ^Widget) {
		kind := self.variant.(Input_Widget_Kind)
		destroy_editor(&kind.editor)
		strings.builder_destroy(&kind.builder)
	}

	// Get the text editor
	kind := widget_kind(self, Input_Widget_Kind)
	e := &kind.editor

	if e.builder == nil {
		make_editor(e, context.allocator, context.allocator)
		begin(e, 0, builder)
		e.set_clipboard = __set_clipboard_string
		e.get_clipboard = __get_clipboard_string
	}

	// Animations
	self.focus_time = animate(self.focus_time, 0.15, .Active in self.state)
	kind.icon_time = animate(kind.icon_time, 0.2, decal != .None)

	// Hover cursor
	if .Hovered in self.state {
		core.cursor_type = .I_Beam
	}

	// Hover
	if point_in_box(core.mouse_pos, self.box) {
		hover_widget(self)
	}

	// Receive and execute editor commands
	if .Active in self.state {
		cmd: Command
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
		// Write allowed and runes available?
		if !read_only && len(core.runes) > 0 {
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
				input_runes(e, {char})
				changed = true
				core.draw_this_frame = true
			}
		}
		if key_pressed(.Backspace) do cmd = .Delete_Word_Left if control_down else .Backspace
		if key_pressed(.Delete) do cmd = .Delete_Word_Right if control_down else .Delete
		if key_pressed(.Enter) {
			cmd = .New_Line
			if multiline {
				if control_down {
					submitted = true
					enter = true
				}
			} else {
				submitted = true
				enter = true
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
		if !info.multiline && (cmd in MULTILINE_COMMANDS) {
			cmd = .None
		}
		if info.read_only && (cmd in EDIT_COMMANDS) {
			cmd = .None
		}
		if cmd != .None {
			editor_execute(e, cmd)
			changed = true
			core.draw_this_frame = true
		}
	}

	if .Active in self.state || submitted {
		text = strings.to_string(builder^)
	}

	// Initial text info
	text_info: Text_Info = {
		text   = text,
		font   = core.style.fonts[.Monospace if monospace else .Medium],
		size   = core.style.content_text_size,
		hidden = info.hidden && len(text) > 0,
	}

	text_origin := [2]f32{self.box.lo.x + 5, 0}

	// Offset text origin based on font size
	if font, ok := &core.fonts[text_info.font].?; ok {
		if font_size, ok := get_font_size(font, text_info.size); ok {
			if info.multiline {
				text_origin.y = self.box.lo.y + (font_size.ascent - font_size.descent) / 2
			} else {
				text_origin.y =
					(self.box.hi.y + self.box.lo.y) / 2 -
					(font_size.ascent - font_size.descent) / 2
			}
		}
	}

	// Make text job
	if text_job, ok := make_text_job(text_info, e, core.mouse_pos - (text_origin - kind.offset));
	   ok {
		// Resolve view offset so the cursor is always shown
		if .Active in self.last_state && text_job.cursor_glyph >= 0 {
			glyph := text_job.glyphs[text_job.cursor_glyph]
			glyph_pos := (text_origin - kind.offset) + glyph.pos
			// The cursor's own bounding box
			cursor_box := Box{glyph_pos + {-1, -2}, glyph_pos + {1, text_job.line_height + 2}}
			// The box we want the cursor to stay in
			inner_box := shrink_box(self.box, 4)
			// Move view offset
			kind.offset.x += max(0, cursor_box.hi.x - inner_box.hi.x)
			if box_width(inner_box) > box_width(cursor_box) {
				kind.offset.x -= max(0, inner_box.lo.x - cursor_box.lo.x)
			}
			if multiline {
				kind.offset.y += max(0, cursor_box.hi.y - inner_box.hi.y)
				if box_height(inner_box) > box_height(cursor_box) {
					kind.offset.y -= max(0, inner_box.lo.y - cursor_box.lo.y)
				}
			}
		} else {
			kind.offset = {}
		}

		// Apply offset after it's been verified!!
		text_origin -= kind.offset

		if self.visible {
			push_clip(self.box)
			// Draw text placeholder
			if len(text_info.text) == 0 {
				text_info := text_info
				text_info.text = info.placeholder
				draw_text(text_origin, text_info, core.style.color.substance)
			}
			// First draw the highlighting behind the text
			if .Active in self.last_state {
				draw_text_highlight(text_job, text_origin, fade(core.style.color.accent, 0.5))
			}
			// Then draw the text
			draw_text_glyphs(text_job, text_origin, core.style.color.content)
			// Draw the cursor in front of the text
			if .Active in self.last_state {
				draw_text_cursor(text_job, text_origin, core.style.color.accent)
			}
			pop_clip()

			// Draw decal
			if kind.icon_time > 0 {
				a := box_height(self.box) / 2
				center := [2]f32{self.box.hi.x, self.box.lo.y} + [2]f32{-a, a}
				switch decal {
				case .None:
					break
				case .Check:
					scale := [2]f32{1 + 4 * kind.icon_time, 5}
					begin_path()
					point(center + {-1, -0.047} * scale)
					point(center + {-0.333, 0.619} * scale)
					point(center + {1, -0.713} * scale)
					stroke_path(2, {0, 255, 120, 255})
					end_path()
				case .Loader:
					draw_loader(center, 5, core.style.color.content)
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

		// Mouse selection
		last_selection := e.selection
		if .Pressed in self.state && text_job.hovered_rune >= 0 {
			if .Pressed not_in self.last_state {
				// Set click anchor
				kind.anchor = text_job.hovered_rune
				// Initial selection
				if self.click_count == 3 {
					editor_execute(e, .Select_All)
				} else {
					e.selection = {text_job.hovered_rune, text_job.hovered_rune}
				}
			}
			switch self.click_count {
			case 2:
				if text_job.hovered_rune < kind.anchor {
					if text_info.text[text_job.hovered_rune] == ' ' {
						e.selection[0] = text_job.hovered_rune
					} else {
						e.selection[0] = max(
							0,
							strings.last_index_any(text_info.text[:text_job.hovered_rune], " \n") +
							1,
						)
					}
					e.selection[1] = strings.index_any(text_info.text[kind.anchor:], " \n")
					if e.selection[1] == -1 {
						e.selection[1] = len(text_info.text)
					} else {
						e.selection[1] += kind.anchor
					}
				} else {
					e.selection[1] = max(
						0,
						strings.last_index_any(text_info.text[:kind.anchor], " \n") + 1,
					)
					if (text_job.hovered_rune > 0 &&
						   text_info.text[text_job.hovered_rune - 1] == ' ') {
						e.selection[0] = 0
					} else {
						e.selection[0] = strings.index_any(
							text_info.text[text_job.hovered_rune:],
							" \n",
						)
					}
					if e.selection[0] == -1 {
						e.selection[0] = len(text_info.text) - text_job.hovered_rune
					}
					e.selection[0] += text_job.hovered_rune
				}

			case 1:
				e.selection[0] = text_job.hovered_rune
			}
		}
		if last_selection != e.selection {
			core.draw_next_frame = true
		}
	}

	// Deactivate when submitted
	if submitted {
		self.state -= {.Active}
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

init_string_input :: proc(using info: ^String_Input_Info, loc := #caller_location) -> bool {
	if value == nil {
		return false
	}
	init_input(info, loc) or_return
	if builder == nil {
		builder = &widget_kind(self, Input_Widget_Kind).builder
	}
	if .Active in (self.state - self.last_state) {
		strings.builder_reset(builder)
		strings.write_string(builder, value^)
	}
	text = value^
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

init_number_input :: proc(using info: ^Number_Input_Info($T), loc := #caller_location) -> bool {
	init_input(info, loc) or_return
	if value == nil {
		return false
	}
	if builder == nil {
		builder = &widget_kind(self, Input_Widget_Kind).builder
	}
	if .Active in (self.state - self.last_state) {
		strings.builder_reset(builder)
		fmt.sbprintf(builder, format.? or_else "{:v}", value^)
	}
	if .Active not_in self.state {
		text = fmt.tprintf(format.? or_else "{:v}", value^)
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
