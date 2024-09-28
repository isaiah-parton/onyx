package onyx

import "core:fmt"

Tabs_Info :: struct {
	using _: Widget_Info,
	index:   ^int,
	options: []string,
}

Tabs_Widget_Kind :: struct {
	timers: [10]f32,
}

init_tabs :: proc(info: ^Tabs_Info, loc := #caller_location) -> bool {
	info.id = hash(loc)
	info.self = get_widget(info.id.?) or_return
	info.options = info.options[:min(len(info.options), 10)]
	info.desired_size = {f32(len(info.options)) * 100, 30}
	return true
}

add_tabs :: proc(using info: ^Tabs_Info) -> bool {
	begin_widget(info) or_return
	defer end_widget()

	kind := widget_kind(self, Tabs_Widget_Kind)

	if point_in_box(core.mouse_pos, self.box) {
		hover_widget(self)
	}

	inner_box := self.box
	if self.visible {
		draw_rounded_box_fill(self.box, core.style.rounding, core.style.color.substance)
	}
	option_rounding := core.style.rounding * (box_height(inner_box) / box_height(self.box))
	option_size := (inner_box.hi.x - inner_box.lo.x) / f32(len(info.options))

	for option, o in options {
		hover_time := kind.timers[o]
		kind.timers[o] = animate(kind.timers[o], 0.1, index^ == o)
		option_box := cut_box_left(&inner_box, option_size)
		if index^ != o {
			if self.state >= {.Hovered} && point_in_box(core.mouse_pos, option_box) {
				if .Clicked in self.state {
					index^ = o
				}
				core.cursor_type = .Pointing_Hand
			}
		}
		if self.visible {
			draw_rounded_box_fill(
				option_box,
				option_rounding,
				fade(core.style.color.foreground, hover_time),
			)
			draw_rounded_box_stroke(
				option_box,
				option_rounding,
				1,
				fade(core.style.color.content, hover_time),
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
				fade(core.style.color.content, 1 if info.index^ == o else 0.5),
			)
		}
	}
	return true
}

tabs :: proc(info: Tabs_Info, loc := #caller_location) -> Tabs_Info {
	info := info
	init_tabs(&info, loc)
	add_tabs(&info)
	return info
}
