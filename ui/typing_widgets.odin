package ui

import "core:strings"
import "core:slice"

Text_Input_Info :: struct {
	using _: Generic_Widget_Info,
	data: [dynamic]u8,
	placeholder: string,
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
	widget := get_widget(info)
	context.allocator = widget.allocator
	widget.box = next_widget_box(info)

	draw_rounded_box_fill(widget.box, core.style.rounding, core.style.color.background)
	draw_rounded_box_stroke(widget.box, core.style.rounding, 1, core.style.color.substance)
	if .Focused in widget.state {
		draw_rounded_box_stroke(expand_box(widget.box, 4), core.style.rounding + 2, 2, core.style.color.accent)
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