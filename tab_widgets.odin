package ui

Tabs_Info :: struct {
	using _: Generic_Widget_Info,
	index: int,
	options: []string,
}

Widget_Variant_Tabs :: struct {
	timers: [dynamic]f32,
}

Tabs_Result :: struct {
	using _: Generic_Widget_Result,
	index: Maybe(int),
}

make_tabs :: proc(info: Tabs_Info, loc := #caller_location) -> Tabs_Info {
	info := info
	info.id = hash(loc)
	info.desired_size = {
		0,
		30,
	}
	return info
}

display_tabs :: proc(info: Tabs_Info, loc := #caller_location) -> (result: Tabs_Result) {
	widget := get_widget(info)
	context.allocator = widget.allocator
	widget.box = next_widget_box(info)
	result.self = widget

	variant := widget_variant(widget, Widget_Variant_Tabs)
	
	draw_rounded_box_fill(widget.box, core.style.rounding, core.style.color.substance)

	box := shrink_box(widget.box, 4)
	option_size := (box.high.x - box.low.x) / f32(len(info.options))
	resize(&variant.timers, len(info.options))
	for option, o in info.options {
		hover_time := variant.timers[o]
		option_box := cut_box_left(&box, option_size)
		if info.index != o {
			if point_in_box(core.mouse_pos, option_box) {
				if was_clicked(result) {
					result.index = o
				}
				core.cursor_type = .POINTING_HAND
			}
		}
		draw_rounded_box_fill(option_box, core.style.rounding, fade(core.style.color.foreground, hover_time))
		draw_text(center(option_box), {
			text = option,
			font = core.style.fonts[.Regular],
			size = 18,
			align_h = .Middle,
			align_v = .Middle,
		}, fade(core.style.color.content, 1 if info.index == o else 0.5))
		variant.timers[o] = animate(variant.timers[o], 0.1, info.index == o)
	}

	commit_widget(widget, point_in_box(core.mouse_pos, widget.box))

	return
}

do_tabs :: proc(info: Tabs_Info, loc := #caller_location) -> Tabs_Result {
	return display_tabs(make_tabs(info, loc))
}