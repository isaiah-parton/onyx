package onyx

import "../../vgo"
import "core:fmt"
import "core:math"
import "core:math/linalg"

Tabs_Info :: struct {
	using _:      Widget_Info,
	index:        ^int,
	options:      []string,
	tab_width:    Maybe(f32),
	closed_index: Maybe(int),
}

Tabs_Widget_Kind :: struct {
	timers: [10]f32,
}

init_tabs :: proc(using info: ^Tabs_Info, loc := #caller_location) -> bool {
	if info == nil do return false
	// Value sanity check
	if index == nil || len(options) == 0 do return false
	if id == 0 do id = hash(loc)
	self = get_widget(id) or_return
	options = options[:min(len(options), 10)]
	self.desired_size = {
		f32(len(options)) * (tab_width.? or_else core.style.visual_size.x),
		core.style.visual_size.y,
	}
	return true
}

add_tabs :: proc(using info: ^Tabs_Info) -> bool {
	begin_widget(info) or_return
	defer end_widget()

	push_id(self.id)
	defer pop_id()

	if layout({box = self.box, isolated = true}) {
		set_side(.Left)
		set_width_percent(100.0 / f32(len(options)))
		set_height_fill()
		for option, o in options {
			push_id(o + 1)
			defer pop_id()

			tab_info := Widget_Info {
				id            = hash("tab"),
				in_state_mask = Widget_State{.Hovered},
			}
			if begin_widget(&tab_info) {
				tab_info.self.open_time = animate(tab_info.self.open_time, 0.15, index^ == o)
				button_behavior(tab_info.self)
				if tab_info.self.visible {
					bg_color := vgo.blend(
					core.style.color.field,
						core.style.color.fg,
						tab_info.self.open_time,
					)
					vgo.fill_box(
						tab_info.self.box,
						{core.style.rounding, core.style.rounding, 0, 0},
						paint = bg_color,
					)
					vgo.push_scissor(vgo.make_box(tab_info.self.box))
					defer vgo.pop_scissor()
					text_layout := vgo.make_text_layout(option, core.style.default_font, 16)
					vgo.fill_text_layout(
						text_layout,
						{
							tab_info.self.box.lo.x + core.style.text_padding.x,
							box_center_y(tab_info.self.box),
						},
						vgo.fade(
							core.style.color.content,
							math.lerp(f32(0.5), f32(1.0), tab_info.self.open_time),
						),
					)
					gradient_size := min(box_width(tab_info.self.box), 80)
					if text_layout.size.x > box_width(tab_info.self.box) - gradient_size {

					}
				}

				if .Hovered in (tab_info.self.state + tab_info.self.last_state) {
					if button({id = hash("close"), text = "\ueb99", style = .Ghost, box = shrink_box(get_box_cut_right(tab_info.self.box, box_height(tab_info.self.box)), 4)}).clicked {
						closed_index = o
					}
				}

				if .Clicked in tab_info.self.state {
					index^ = o
				}

				end_widget()
			}
		}
	}

	return true
}

tabs :: proc(info: Tabs_Info, loc := #caller_location) -> Tabs_Info {
	info := info
	if init_tabs(&info, loc) {
		add_tabs(&info)
	}
	return info
}

init_box_tabs :: proc(using info: ^Tabs_Info, loc := #caller_location) -> bool {
	return init_tabs(info)
}

add_box_tabs :: proc(using info: ^Tabs_Info) -> bool {
	begin_widget(info) or_return
	defer end_widget()

	kind := widget_kind(self, Tabs_Widget_Kind)

	if point_in_box(core.mouse_pos, self.box) {
		hover_widget(self)
	}

	inner_box := self.box
	if self.visible {
		vgo.fill_box(self.box, core.style.rounding, core.style.color.substance)
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
			vgo.fill_box(
				option_box,
				option_rounding,
				paint = vgo.fade(core.style.color.fg, hover_time),
			)
			vgo.stroke_box(
				option_box,
				option_rounding,
				1,
				paint = vgo.fade(core.style.color.content, hover_time),
			)
			vgo.fill_text_aligned(
				option,
				core.style.default_font,
				18,
				box_center(option_box),
				.Center,
				.Center,
				paint = vgo.fade(core.style.color.content, 1 if info.index^ == o else 0.5),
			)
		}
	}
	return true
}

box_tabs :: proc(info: Tabs_Info, loc := #caller_location) -> Tabs_Info {
	info := info
	if init_box_tabs(&info, loc) {
		add_box_tabs(&info)
	}
	return info
}
