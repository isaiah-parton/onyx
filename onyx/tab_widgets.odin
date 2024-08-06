package onyx

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
		f32(len(info.options)) * 100,
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

	inner_box := shrink_box(widget.box, 3)
	option_rounding := core.style.rounding * (box_height(inner_box) / box_height(widget.box))
	option_size := (inner_box.hi.x - inner_box.lo.x) / f32(len(info.options))
	resize(&variant.timers, len(info.options))
	for option, o in info.options {
		hover_time := variant.timers[o]
		option_box := cut_box_left(&inner_box, option_size)
		if info.index != o {
			if widget.state >= {.Hovered} && point_in_box(core.mouse_pos, option_box) {
				if was_clicked(result) {
					result.index = o
				}
				core.cursor_type = .POINTING_HAND
			}
		}
		draw_rounded_box_fill(option_box, option_rounding, fade(core.style.color.foreground, hover_time))
		draw_text(box_center(option_box), {
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