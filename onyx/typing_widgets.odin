package onyx

import "core:fmt"
import "core:math/linalg"
import "core:mem"
import "core:slice"
import "core:strings"
import "core:time"
import "core:unicode"

import "tedit"

Text_Input_Decal :: enum {
	None,
	Check,
	Loader,
}

Text_Input_Info :: struct {
	using _:                      Widget_Info,
	content:                      ^strings.Builder,
	placeholder:                  string,
	numeric, integer:             bool,
	multiline, read_only, hidden: bool,
	decal:                        Text_Input_Decal,
	undecorated:                  bool,
	changed, submitted:           bool,
}

Text_Input_Widget_Kind :: struct {
	editor:    tedit.Text_Editor,
	builder:   strings.Builder,
	anchor:    int,
	icon_time: f32,
	offset:    [2]f32,
}

init_text_input :: proc(info: ^Text_Input_Info, loc := #caller_location) -> bool {
	info.id = hash(loc)
	info.self = get_widget(info.id.?) or_return
	info.sticky = true
	info.desired_size = core.style.visual_size
	return true
}

add_text_input :: proc(using info: ^Text_Input_Info) -> bool {
	using tedit

	// A text input without content will not be displayed
	if info.content == nil {
		return false
	}

	begin_widget(info) or_return
	defer end_widget()

	if self.visible && !undecorated {
		draw_rounded_box_fill(self.box, core.style.rounding, core.style.color.background)
	}

	if content == nil {
		return false
	}

	kind := widget_kind(self, Text_Input_Widget_Kind)
	e := &kind.editor

	// Cleanup procedure
	self.on_death = proc(self: ^Widget) {
		kind := self.variant.(Text_Input_Widget_Kind)
		destroy_text_editor(&kind.editor)
		strings.builder_destroy(&kind.builder)
	}

	if .Active in self.state {
		if .Active not_in self.last_state {
			strings.builder_reset(&kind.builder)
			strings.write_string(&kind.builder, info.content^)
		}
		if (core.focused_widget != core.last_focused_widget) && !key_down(.Left_Control) {
			self.state -= {.Active}
		}
	} else {
		if .Pressed in (self.state - self.last_state) {
			self.state += {.Active}
		}
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
			if info.numeric {
				allowed = "0123456789."
				if info.integer || strings.contains_rune(content^, '.') {
					allowed = allowed[:len(allowed) - 1]
				}
			}
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
		if !info.multiline && (cmd in MULTILINE_COMMANDS) {
			cmd = .None
		}
		if info.read_only && (cmd in EDIT_COMMANDS) {
			cmd = .None
		}
		if cmd != .None {
			text_editor_execute(e, cmd)
			changed = true
			core.draw_this_frame = true
		}
	}

	// Initial text info
	text_info: Text_Info = {
		text   = strings.to_string(kind.builder) if .Active in self.state else info.content^,
		font   = core.style.fonts[.Medium],
		size   = core.style.content_text_size,
		hidden = info.hidden,
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

	// Initialize editor state when just focused
	if .Active in (self.state - self.last_state) {
		make_text_editor(e, context.allocator, context.allocator)
		begin(e, 0, &kind.builder)
		e.set_clipboard = __set_clipboard_string
		e.get_clipboard = __get_clipboard_string
	}

	// Make text job
	if text_job, ok := make_text_job(text_info, e, core.mouse_pos - (text_origin - kind.offset));
	   ok {
		// Resolve view offset so the cursor is always shown
		if .Active in self.last_state {
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
				if multiline {
					draw_rounded_box_stroke(
						self.box,
						core.style.rounding,
						1 + self.focus_time,
						interpolate_colors(
							self.focus_time,
							core.style.color.substance,
							core.style.color.accent,
						),
					)
				} else {
					draw_box_fill(
						get_box_cut_bottom(self.box, 1 + self.focus_time),
						interpolate_colors(
							self.focus_time,
							core.style.color.substance,
							core.style.color.accent,
						),
					)
				}
			}

			// Draw disabled overlay
			if self.disable_time > 0 {
				draw_rounded_box_fill(
					self.box,
					core.style.rounding,
					fade(core.style.color.foreground, self.disable_time * 0.5),
				)
			}

			if !info.undecorated {
				draw_rounded_box_mask_fill(
					self.box,
					core.style.rounding,
					core.style.color.foreground,
				)
			}
		}

		// Mouse selection
		last_selection := e.selection
		if .Pressed in self.state && text_job.hovered_rune != -1 {
			if .Pressed not_in self.last_state {
				// Set click anchor
				kind.anchor = text_job.hovered_rune
				// Initial selection
				if self.click_count == 3 {
					text_editor_execute(e, .Select_All)
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

	if changed {
		delete(content^)
		content^ = strings.clone(strings.to_string(kind.builder))
	}
	return true
}

text_input :: proc(info: Text_Input_Info, loc := #caller_location) -> Text_Input_Info {
	info := info
	init_text_input(&info, loc)
	add_text_input(&info)
	return info
}
