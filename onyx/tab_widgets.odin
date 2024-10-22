package onyx

import "core:fmt"
import "core:math"
import "core:math/linalg"

Tabs_Info :: struct {
	using _:      Widget_Info,
	index:        ^int,
	options:      []string,
	tab_width:		Maybe(f32),
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
	desired_size = {f32(len(options)) * (tab_width.? or_else core.style.visual_size.x), core.style.visual_size.y}
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
				id = hash("tab"),
				in_state_mask = Widget_State{.Hovered},
			}
			if begin_widget(&tab_info) {
				tab_info.self.open_time = animate(tab_info.self.open_time, 0.15, index^ == o)
				button_behavior(tab_info.self)
				if tab_info.self.visible {
					background_color := alpha_blend_colors(
						core.style.color.background,
						core.style.color.foreground,
						tab_info.self.open_time,
					)
					shape_index := add_shape_box(
						tab_info.self.box,
						{core.style.rounding, core.style.rounding, 0, 0},
					)
					render_shape(shape_index, background_color)
					push_scissor(tab_info.self.box, shape_index)
					if text_job, ok := make_text_job(
						{
							text = option,
							font = core.style.default_font,
							size = 16,
							align_v = .Middle,
						},
					); ok {
						draw_text_glyphs(
							text_job,
							{tab_info.self.box.lo.x + core.style.label_padding.x, box_center_y(tab_info.self.box)},
							fade(
								core.style.color.content,
								math.lerp(f32(0.5), f32(1.0), tab_info.self.open_time),
							),
						)
						gradient_size := min(box_width(tab_info.self.box), 80)
						if text_job.size.x > box_width(tab_info.self.box) - gradient_size {
							draw_horizontal_box_gradient(
								get_box_cut_right(tab_info.self.box, gradient_size),
								fade(background_color, 0),
								background_color,
							)
						}
					}
					pop_scissor()
				}

				if .Hovered in (tab_info.self.state + tab_info.self.last_state) {
					if button({
						id = hash("close"),
						text = "\ueb99",
						style = .Ghost,
						box = shrink_box(get_box_cut_right(tab_info.self.box, box_height(tab_info.self.box)), 4),
					}).clicked {
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
					font = core.style.default_font,
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

box_tabs :: proc(info: Tabs_Info, loc := #caller_location) -> Tabs_Info {
	info := info
	if init_box_tabs(&info, loc) {
		add_box_tabs(&info)
	}
	return info
}
