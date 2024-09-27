package onyx

import "core:fmt"

Tabs_Info :: struct {
	using _: Widget_Info,
	index:   ^int,
	options: []string,
}

Tabs :: struct {
	using info: Tabs_Info,
	timers: [10]f32,
}

Tabs_Result :: struct {
	using _: Widget_Result,
}

make_tabs :: proc(info: Tabs_Info, loc := #caller_location) -> (tabs: Tabs, ok: bool) {
	tabs.info = info
	tabs.id = hash(loc)
	tabs.options = tabs.options[:min(len(tabs.options), 10)]
	tabs.desired_size = {f32(len(tabs.options)) * 100, 30}
	return info
}

add_tabs :: proc(tabs: Tabs) -> (result: Tabs_Result, ok: bool) #optional_ok {
	begin_widget(tabs) or_return

	if point_in_box(core.mouse_pos, widget.box) {
		hover_widget(widget)
	}

	inner_box := widget.box
	if widget.visible {
		draw_rounded_box_fill(widget.box, core.style.rounding, core.style.color.substance)
	}
	option_rounding := core.style.rounding * (box_height(inner_box) / box_height(widget.box))
	option_size := (inner_box.hi.x - inner_box.lo.x) / f32(len(info.options))

	for option, o in info.options {
		tabs.timers[o] = animate(tabs.timers[o], 0.1, info.index == o)
		option_box := cut_box_left(&inner_box, option_size)
		if info.index != o {
			if widget.state >= {.Hovered} && point_in_box(core.mouse_pos, option_box) {
				if was_clicked(result) {
					result.index = o
				}
				core.cursor_type = .Pointing_Hand
			}
		}
		if widget.visible {
			draw_rounded_box_fill(
				option_box,
				option_rounding,
				fade(core.style.color.foreground, tabs.timers[o]),
			)
			draw_rounded_box_stroke(
				option_box,
				option_rounding,
				1,
				fade(core.style.color.content, tabs.timers[o]),
			)
			draw_text(
				box_center(option_box),
				{
					text = option,
					font = core.style.fonts[.Regular],
					size = 18,
					align_h = .Middle,
					align_v = .Middle,
				},
				fade(core.style.color.content, 1 if info.index == o else 0.5),
			)
		}
	}

	end_widget()
	return
}

tabs :: proc(info: Tabs_Info, loc := #caller_location) -> (result: Tabs_Result, ok: bool) {
	return add_tabs(make_tabs(info, loc) or_return)
}
