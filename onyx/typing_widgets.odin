package onyx

import "core:fmt"
import "core:strings"
import "core:slice"
import "core:time"

Text_Input_Info :: struct {
	using _: Generic_Widget_Info,
	builder: ^strings.Builder,
	placeholder: string,
	multiline,
	read_only: bool,
}

Text_Input_Widget_Variant :: struct {
	editor: Text_Editor,
}

Text_Input_Result :: struct {
	using _: Generic_Widget_Result,
}

make_text_input :: proc(info: Text_Input_Info, loc := #caller_location) -> Text_Input_Info {
	info := info
	info.id = hash(loc)
	info.desired_size = {
		200,
		core.style.text_input_height,
	}
	return info
}

display_text_input :: proc(info: Text_Input_Info) -> (result: Text_Input_Result) {
	if info.builder == nil {
		return
	}

	widget := get_widget(info)
	context.allocator = widget.allocator
	widget.box = next_widget_box(info)
	widget.draggable = true

	v := widget.variant
	variant := widget_variant(widget, Text_Input_Widget_Variant)
	e := &variant.editor
	if v == nil {
		// init_text_editor(e, widget.allocator, widget.allocator)
	}

	widget.focus_time = animate(widget.focus_time, 0.15, .Focused in widget.state)

	text_info: Text_Info = {
		font = core.style.fonts[.Regular],
		text = strings.to_string(info.builder^),
		spacing = 1,
		size = core.style.content_text_size,
	}

	text_origin: [2]f32 = {
		widget.box.lo.x + 5, 
		0,
	}

	if font, ok := &core.fonts[text_info.font].?; ok {
		if font_size, ok := get_font_size(font, text_info.size); ok {
			if info.multiline {
				text_origin.y = widget.box.lo.y + (font_size.ascent - font_size.descent) / 2
			} else {
				text_origin.y = (widget.box.hi.y + widget.box.lo.y) / 2 - (font_size.ascent - font_size.descent) / 2
			}
		}
	}

	if .Focused in (widget.state - widget.last_state) {
		begin(e, 0, info.builder)
		e.set_clipboard = set_clipboard_string
		e.get_clipboard = get_clipboard_string
	}

	result.self = widget

	begin_layer({
		box = widget.box,
		options = {.Attached},
	})
	if widget.visible || .Focused in widget.state {
		draw_rounded_box_fill(widget.box, core.style.rounding, core.style.color.background)
		draw_rounded_box_stroke(widget.box, core.style.rounding, 1, core.style.color.substance)
		if len(text_info.text) == 0 {
			text_info := text_info
			text_info.text = info.placeholder
			draw_text(text_origin, text_info, fade(core.style.color.content, 0.5))
		}
		if .Focused in widget.state {
			// draw_interactive_text(result, e, text_origin, text_info, core.style.color.content)
		} else {
			draw_text(text_origin, text_info, core.style.color.content)
		}
		if widget.focus_time > 0 {
			draw_rounded_box_stroke(expand_box(widget.box, 4), core.style.rounding + 2.5, 2, fade(core.style.color.accent, widget.focus_time))
		}
	}
	end_layer()

	if .Focused in widget.state {
		cmd: Command
		control_down := key_down(.LEFT_CONTROL) || key_down(.RIGHT_CONTROL)
		shift_down := key_down(.LEFT_SHIFT) || key_down(.RIGHT_SHIFT)
		if control_down {
			if key_pressed(.C) do cmd = .Copy
			if key_pressed(.A) do cmd = .Select_All
			if !info.read_only {
				if key_pressed(.V) do cmd = .Paste
				if key_pressed(.X) do cmd = .Cut
				if key_pressed(.Z) do cmd = .Undo
				if key_pressed(.Y) do cmd = .Redo
			}
		}
		if !info.read_only {
			input_runes(e, core.runes[:])
			if key_pressed(.BACKSPACE) do cmd = .Delete_Word_Left if control_down else .Backspace
			if key_pressed(.DELETE) do cmd = .Delete
			if key_pressed(.ENTER) do cmd = .New_Line
		}
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
		if cmd != .None {
			perform_command(e, cmd)
			core.draw_next_frame = true
		}
	}

	if .Hovered in widget.state {
		core.cursor_type = .IBEAM
	}

	commit_widget(widget, point_in_box(core.mouse_pos, widget.box))

	return
}

do_text_input :: proc(info: Text_Input_Info, loc := #caller_location) -> Text_Input_Result {
	return display_text_input(make_text_input(info, loc))
}