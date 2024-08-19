package onyx

import "core:fmt"
import "core:slice"
import "core:strings"
import "core:time"

Text_Input_Decal :: enum {
	None,
	Check,
	Loader,
}

Text_Input_Info :: struct {
	using _:                      Generic_Widget_Info,
	builder:                      ^strings.Builder,
	placeholder:                  string,
	multiline, read_only, hidden: bool,
	decal:                        Text_Input_Decal,
}

Text_Input_Widget_Variant :: struct {
	editor:    Text_Editor,
	anchor:    int,
	icon_time: f32,
}

Text_Input_Result :: struct {
	using _: Generic_Widget_Result,
}

make_text_input :: proc(info: Text_Input_Info, loc := #caller_location) -> Text_Input_Info {
	info := info
	info.id = hash(loc)
	info.desired_size = {200, 30}
	return info
}

add_text_input :: proc(info: Text_Input_Info) -> (result: Text_Input_Result) {
	if info.builder == nil {
		return
	}

	widget, ok := begin_widget(info)
	if !ok do return

	widget.draggable = true
	widget.is_field = true

	result.self = widget

	variant := widget_variant(widget, Text_Input_Widget_Variant)
	e := &variant.editor

	widget.focus_time = animate(widget.focus_time, 0.15, .Focused in widget.state)
	variant.icon_time = animate(variant.icon_time, 0.2, info.decal != .None)

	text_info: Text_Info = {
		font   = core.style.fonts[.Medium],
		text   = strings.to_string(info.builder^),
		size   = core.style.content_text_size,
		hidden = info.hidden,
	}

	text_origin: [2]f32 = {widget.box.lo.x + 5, 0}

	if font, ok := &core.fonts[text_info.font].?; ok {
		if font_size, ok := get_font_size(font, text_info.size); ok {
			if info.multiline {
				text_origin.y = widget.box.lo.y + (font_size.ascent - font_size.descent) / 2
			} else {
				text_origin.y =
					(widget.box.hi.y + widget.box.lo.y) / 2 -
					(font_size.ascent - font_size.descent) / 2
			}
		}
	}

	if .Focused in (widget.state - widget.last_state) {
		make_text_editor(e, widget.allocator, widget.allocator)
		begin(e, 0, info.builder)
		e.set_clipboard = set_clipboard_string
		e.get_clipboard = get_clipboard_string
	}

	if .Focused in widget.state {
		cmd: Command
		control_down := key_down(.LEFT_CONTROL) || key_down(.RIGHT_CONTROL)
		shift_down := key_down(.LEFT_SHIFT) || key_down(.RIGHT_SHIFT)
		if control_down {
			if key_pressed(.A) do cmd = .Select_All
			if key_pressed(.C) do cmd = .Copy
			if key_pressed(.V) do cmd = .Paste
			if key_pressed(.X) do cmd = .Cut
			if key_pressed(.Z) do cmd = .Undo
			if key_pressed(.Y) do cmd = .Redo
		}
		if !info.read_only {
			if len(core.runes) > 0 {
				widget.state += {.Changed}
			}
			input_runes(e, core.runes[:])
		}
		if key_pressed(.BACKSPACE) do cmd = .Delete_Word_Left if control_down else .Backspace
		if key_pressed(.DELETE) do cmd = .Delete_Word_Right if control_down else .Delete
		if key_pressed(.ENTER) do cmd = .New_Line
		if key_pressed(.LEFT) {
			if shift_down do cmd = .Select_Word_Left if control_down else .Select_Left
			else do cmd = .Word_Left if control_down else .Left
		}
		if key_pressed(.RIGHT) {
			if shift_down do cmd = .Select_Word_Right if control_down else .Select_Right
			else do cmd = .Word_Right if control_down else .Right
		}
		if key_pressed(.UP) {
			if shift_down do cmd = .Select_Up
			else do cmd = .Up
		}
		if key_pressed(.DOWN) {
			if shift_down do cmd = .Select_Down
			else do cmd = .Down
		}
		if key_pressed(.HOME) {
			cmd = .Select_Line_Start if control_down else .Line_Start
		}
		if key_pressed(.END) {
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
			widget.state += {.Changed}
			core.draw_next_frame = true
		}
	}

	// Make text job
	if text_job, ok := make_text_job(text_info, e, core.mouse_pos - text_origin); ok {
		if widget.visible || .Focused in widget.state {
			draw_rounded_box_fill(widget.box, core.style.rounding, core.style.color.background)
			draw_rounded_box_stroke(widget.box, core.style.rounding, 1, core.style.color.substance)
			if len(text_info.text) == 0 {
				text_info := text_info
				text_info.text = info.placeholder
				draw_text(text_origin, text_info, core.style.color.substance)
			}
			if .Focused in widget.state {
				draw_text_highlight(text_job, text_origin, fade(core.style.color.accent, 0.5))
			}
			draw_text_glyphs(text_job, text_origin, core.style.color.content)
			if .Focused in widget.state {
				draw_text_cursor(text_job, text_origin, core.style.color.accent)
			}
			if widget.focus_time > 0 {
				draw_rounded_box_stroke(
					expand_box(widget.box, 4),
					core.style.rounding * 1.5,
					2,
					fade(core.style.color.accent, widget.focus_time),
				)
			}
			if variant.icon_time > 0 {
				a := box_height(widget.box) / 2
				center := [2]f32{widget.box.hi.x, widget.box.lo.y} + [2]f32{-a, a}
				switch info.decal {
				case .None:
					break
				case .Check:
					scale := [2]f32{1 + 4 * variant.icon_time, 5}
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
			if widget.disable_time > 0 {
				draw_rounded_box_fill(
					widget.box,
					core.style.rounding,
					fade(core.style.color.background, widget.disable_time * 0.5),
				)
			}
		}

		// Mouse selection
		last_selection := e.selection
		if .Pressed in widget.state && text_job.hovered_rune != -1 {
			if .Pressed not_in widget.last_state {
				// Set click anchor
				variant.anchor = text_job.hovered_rune
				// Initial selection
				if widget.click_count == 3 {
					text_editor_execute(e, .Select_All)
				} else {
					e.selection = {text_job.hovered_rune, text_job.hovered_rune}
				}
			}
			switch widget.click_count {

			case 2:
				if text_job.hovered_rune < variant.anchor {
					if text_info.text[text_job.hovered_rune] == ' ' {
						e.selection[0] = text_job.hovered_rune
					} else {
						e.selection[0] = max(
							0,
							strings.last_index_any(text_info.text[:text_job.hovered_rune], " \n") +
							1,
						)
					}
					e.selection[1] = strings.index_any(text_info.text[variant.anchor:], " \n")
					if e.selection[1] == -1 {
						e.selection[1] = len(text_info.text)
					} else {
						e.selection[1] += variant.anchor
					}
				} else {
					e.selection[1] = max(
						0,
						strings.last_index_any(text_info.text[:variant.anchor], " \n") + 1,
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

	if .Hovered in widget.state {
		core.cursor_type = .IBEAM
	}

	if point_in_box(core.mouse_pos, widget.box) {
		widget.try_hover = true
	}

	end_widget()
	return
}

do_text_input :: proc(info: Text_Input_Info, loc := #caller_location) -> Text_Input_Result {
	return add_text_input(make_text_input(info, loc))
}
