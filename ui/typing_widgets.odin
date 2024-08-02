package ui

import "core:fmt"
import "core:strings"
import "core:slice"

import "core:text/edit"

Text_Input_Info :: struct {
	using _: Generic_Widget_Info,
	builder: ^strings.Builder,
	placeholder: string,
	multiline,
	read_only: bool,
}

Text_Input_Widget_Variant :: struct {
	state: edit.State,
}

Text_Input_Result :: struct {
	using _: Generic_Widget_Result,
}

make_text_input :: proc(info: Text_Input_Info, loc := #caller_location) -> Text_Input_Info {
	info := info
	info.id = hash(loc)
	info.desired_size = {
		200,
		30,
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
	result.self = widget

	v := widget.variant
	variant := widget_variant(widget, Text_Input_Widget_Variant)
	s := &variant.state
	if v == nil {
		edit.init(s, widget.allocator, widget.allocator)
	}

	text_info: Text_Info = {
		font = core.style.fonts[.Regular],
		text = strings.to_string(info.builder^),
		size = core.style.content_text_size,
		align_v = .Middle,
	}

	if .Focused in (widget.state - widget.last_state) {
		edit.begin(s, 0, info.builder)
	}

	if widget.visible || .Focused in widget.state {
		draw_rounded_box_fill(widget.box, core.style.rounding, core.style.color.background)
		draw_rounded_box_stroke(widget.box, core.style.rounding, 1, core.style.color.substance)
		if .Focused in widget.state {
			draw_rounded_box_stroke(expand_box(widget.box, 4), core.style.rounding + 2, 2, core.style.color.accent)
			draw_interactive_text(result, s, {widget.box.low.x + 5, (widget.box.high.y + widget.box.low.y) / 2}, text_info, core.style.color.content)
		} else {
			draw_text({widget.box.low.x + 5, (widget.box.high.y + widget.box.low.y) / 2}, text_info, core.style.color.content)
		}
	}

	if .Focused in widget.state {
		cmd: edit.Command
		control_down := key_down(.LEFT_CONTROL) || key_down(.RIGHT_CONTROL)
		shift_down := key_down(.LEFT_SHIFT) || key_down(.RIGHT_SHIFT)
		if control_down {
			if key_pressed(.C) do cmd = .Copy
			if key_pressed(.A) do cmd = .Select_All
			if !info.read_only {
				if key_pressed(.V) do cmd = .Paste
				if key_pressed(.X) do cmd = .Cut
			}
		}
		if !info.read_only {
			edit.input_runes(s, core.runes[:])
			if key_pressed(.BACKSPACE) do cmd = .Backspace
			if key_pressed(.DELETE) do cmd = .Delete
		}
		if key_pressed(.LEFT) {
			cmd = .Left
			if shift_down {
				cmd = .Select_Word_Left if control_down else .Select_Left
			}
		}
		if key_pressed(.RIGHT) {
			cmd = .Right
			if shift_down {
				cmd = .Select_Word_Right if control_down else .Select_Right
			}
		}
		if key_pressed(.UP) {
			cmd = .Up
			if shift_down {
				cmd = .Select_Up
			}
		}
		if key_pressed(.DOWN) {
			cmd = .Down
			if shift_down {
				cmd = .Select_Down
			}
		}
		if !info.multiline && (cmd in edit.MULTILINE_COMMANDS) {
			cmd = .None
		}
		if cmd != .None {
			edit.perform_command(s, cmd)
			core.draw_next_frame = true
		}
	} else if .Focused in widget.last_state {
		edit.end(s)
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