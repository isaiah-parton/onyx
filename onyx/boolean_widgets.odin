package onyx

import "core:fmt"
import "core:math"
import "core:math/ease"
import "core:math/linalg"

@(private = "file")
SIZE :: 20
@(private = "file")
TEXT_PADDING :: 5

Boolean_Widget_Info :: struct {
	using _:   Widget_Info,
	state:     ^bool,
	text:      string,
	text_side: Maybe(Side),
	text_job:  Text_Job,
	toggled:   bool,
}

Boolean_Widget_Kind :: struct {
	state_time: f32,
}

boolean_widget_behavior :: proc(
	widget: ^Widget,
	info: Boolean_Widget_Info,
) -> ^Boolean_Widget_Kind {
	kind := widget_kind(widget, Boolean_Widget_Kind)
	kind.state_time = animate(kind.state_time, 0.15, info.state^)
	return kind
}

init_boolean_widget :: proc(info: ^Boolean_Widget_Info, loc := #caller_location) -> bool {
	info.id = hash(loc)
	info.self = get_widget(info.id) or_return
	info.text_side = info.text_side.? or_else .Left
	if len(info.text) > 0 {
		if text_job, ok := make_text_job(
			{font = core.style.fonts[.Regular], size = 18, text = info.text},
		); ok {
			info.text_job = text_job
			if info.text_side == .Bottom || info.text_side == .Top {
				info.desired_size.x = max(SIZE, info.text_job.size.x)
				info.desired_size.y = SIZE + info.text_job.size.y
			} else {
				info.desired_size.x = SIZE + info.text_job.size.x + TEXT_PADDING * 2
				info.desired_size.y = SIZE
			}
		}
	} else {
		info.desired_size = SIZE
	}
	info.fixed_size = true
	return true
}

add_checkbox :: proc(using info: ^Boolean_Widget_Info) -> bool {
	begin_widget(info) or_return
	defer end_widget()

	button_behavior(self)

	if self.visible {
		icon_box: Box
		if len(info.text) > 0 {
			switch info.text_side {
			case .Left:
				icon_box = {self.box.lo, SIZE}
			case .Right:
				icon_box = {{self.box.hi.x - SIZE, self.box.lo.y}, SIZE}
			case .Top:
				icon_box = {{box_center_x(self.box) - SIZE / 2, self.box.hi.y - SIZE}, SIZE}
			case .Bottom:
				icon_box = {{box_center_x(self.box) - SIZE / 2, self.box.lo.y}, SIZE}
			}
			icon_box.lo = linalg.floor(icon_box.lo)
			icon_box.hi += icon_box.lo
		} else {
			icon_box = self.box
		}
		if self.hover_time > 0 {
			draw_rounded_box_fill(
				self.box,
				core.style.rounding,
				fade(core.style.color.substance, 0.5 * self.hover_time),
			)
		}
		opacity: f32 = 0.5 if self.disabled else 1
		draw_rounded_box_fill(
			icon_box,
			core.style.rounding,
			fade(core.style.color.accent if state^ else core.style.color.substance, opacity),
		)
		center := box_center(icon_box)
		// Paint icon
		if state^ {
			draw_check(center, SIZE / 4, core.style.color.background)
		}
		// Paint text
		text_pos: [2]f32
		if len(info.text) > 0 {
			switch info.text_side {
			case .Left:
				text_pos = {icon_box.hi.x + TEXT_PADDING, center.y - info.text_job.size.y / 2}
			case .Right:
				text_pos = {icon_box.lo.x - TEXT_PADDING, center.y - info.text_job.size.y / 2}
			case .Top:
				text_pos = self.box.lo
			case .Bottom:
				text_pos = {self.box.lo.x, self.box.hi.y - info.text_job.size.y}
			}
			draw_text_glyphs(info.text_job, text_pos, fade(core.style.color.content, opacity))
			// if self.hover_time > 0 {
			// 	draw_box_fill(
			// 		{
			// 			{text_pos.x, text_pos.y + info.text_job.ascent + 1},
			// 			{
			// 				text_pos.x + info.text_job.size.x,
			// 				text_pos.y + info.text_job.ascent + 2,
			// 			},
			// 		},
			// 		fade(core.style.color.content, self.hover_time),
			// 	)
			// }
		}
	}

	if .Clicked in self.state {
		state^ = !state^
		toggled = true
	}

	return true
}

checkbox :: proc(info: Boolean_Widget_Info, loc := #caller_location) -> Boolean_Widget_Info {
	info := info
	if init_boolean_widget(&info, loc) {
		add_checkbox(&info)
	}
	return info
}

Toggle_Switch_Info :: Boolean_Widget_Info

init_toggle_switch :: proc(using info: ^Toggle_Switch_Info, loc := #caller_location) -> bool {
	text_side = text_side.? or_else .Right
	desired_size = [2]f32{2, 1} * core.style.visual_size.y * 0.75
	if len(text) > 0 {
		text_job = make_text_job(
			{font = core.style.fonts[.Regular], size = 18, text = text},
		) or_return
		desired_size.x += text_job.size.x + TEXT_PADDING
	}
	fixed_size = true
	id = hash(loc)
	self = get_widget(id) or_return
	return true
}

add_toggle_switch :: proc(using info: ^Toggle_Switch_Info) -> bool {
	begin_widget(info) or_return
	defer end_widget()

	variant := widget_kind(self, Boolean_Widget_Kind)

	button_behavior(self)

	variant.state_time = animate(variant.state_time, 0.2, info.state^)
	how_on := ease.cubic_in_out(variant.state_time)

	if self.visible {
		outer_radius := box_height(self.box) / 2
		switch_box: Box = self.box
		switch text_side {
		case .Left:
			switch_box = get_box_cut_right(self.box, box_height(switch_box) * 2)
		case .Right:
			switch_box = get_box_cut_left(self.box, box_height(switch_box) * 2)
		}
		inner_box := shrink_box(switch_box, 2)
		inner_radius := box_height(inner_box) / 2
		lever_center: [2]f32 = {
			inner_box.lo.x +
			inner_radius +
			(box_width(inner_box) - box_height(inner_box)) * how_on,
			box_center_y(inner_box),
		}

		draw_rounded_box_fill(
			switch_box,
			outer_radius,
			interpolate_colors(how_on, core.style.color.substance, core.style.color.accent),
		)
		draw_circle_fill(lever_center, inner_radius, core.style.color.content)

		switch text_side {
		case .Left:
			draw_text_glyphs(
				text_job,
				{self.box.lo.x, box_center_y(self.box) - text_job.size.y / 2},
				core.style.color.content,
			)
		case .Right:
			draw_text_glyphs(
				text_job,
				{self.box.hi.x - text_job.size.x, box_center_y(self.box) - text_job.size.y / 2},
				core.style.color.content,
			)
		}
	}

	if .Clicked in self.state {
		state^ = !state^
		toggled = true
	}

	return true
}

toggle_switch :: proc(info: Toggle_Switch_Info, loc := #caller_location) -> Toggle_Switch_Info {
	info := info
	if init_toggle_switch(&info, loc) {
		add_toggle_switch(&info)
	}
	return info
}

Radio_Button_Info :: Boolean_Widget_Info

add_radio_button :: proc(using info: ^Radio_Button_Info) -> bool {
	begin_widget(info) or_return
	defer end_widget()

	kind := widget_kind(self, Boolean_Widget_Kind)
	kind.state_time = animate(kind.state_time, 0.15, info.state^)

	button_behavior(self)

	if self.visible {
		icon_box: Box
		if len(info.text) > 0 {
			switch info.text_side {
			case .Left:
				icon_box = {self.box.lo, SIZE}
			case .Right:
				icon_box = {{self.box.hi.x - SIZE, self.box.lo.y}, SIZE}
			case .Top:
				icon_box = {{box_center_x(self.box) - SIZE / 2, self.box.hi.y - SIZE}, SIZE}
			case .Bottom:
				icon_box = {{box_center_x(self.box) - SIZE / 2, self.box.lo.y}, SIZE}
			}
			icon_box.lo = linalg.floor(icon_box.lo)
			icon_box.hi += icon_box.lo
		} else {
			icon_box = self.box
		}
		icon_center := box_center(icon_box)

		if self.hover_time > 0 {
			draw_box_fill(
				{{self.box.lo.x + box_height(self.box) / 2, self.box.lo.y}, self.box.hi},
				fade(core.style.color.substance, 0.5 * self.hover_time),
			)
		}

		state_time := ease.circular_in_out(kind.state_time)
		draw_circle_fill(
			icon_center,
			SIZE / 2,
			interpolate_colors(state_time, core.style.color.substance, core.style.color.accent),
		)
		if state_time > 0 {
			draw_circle_fill(
				icon_center,
				(SIZE / 2 - 5) * kind.state_time,
				fade(core.style.color.background, state_time),
			)
		}
		// Paint text
		if len(info.text) > 0 {
			switch info.text_side {
			case .Left:
				draw_text_glyphs(
					info.text_job,
					{icon_box.hi.x + TEXT_PADDING, icon_center.y - info.text_job.size.y / 2},
					core.style.color.content,
				)
			case .Right:
				draw_text_glyphs(
					info.text_job,
					{icon_box.lo.x - TEXT_PADDING, icon_center.y - info.text_job.size.y / 2},
					core.style.color.content,
				)
			case .Top:
				draw_text_glyphs(info.text_job, self.box.lo, core.style.color.content)
			case .Bottom:
				draw_text_glyphs(
					info.text_job,
					{self.box.lo.x, self.box.hi.y - info.text_job.size.y},
					core.style.color.content,
				)
			}
		}
		if self.disable_time > 0 {
			draw_box_fill(self.box, fade(core.style.color.foreground, self.disable_time * 0.5))
		}
	}

	if .Clicked in self.state {
		toggled = true
	}

	return true
}

radio_button :: proc(info: Radio_Button_Info, loc := #caller_location) -> Radio_Button_Info {
	info := info
	if init_boolean_widget(&info, loc) {
		add_radio_button(&info)
	}
	return info
}
