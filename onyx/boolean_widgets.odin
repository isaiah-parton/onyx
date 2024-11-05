package onyx

import "../../vgo"
import "core:fmt"
import "core:math"
import "core:math/ease"
import "core:math/linalg"

Boolean_Widget_Info :: struct {
	using _:     Widget_Info,
	state:       ^bool,
	text:        string,
	text_side:   Maybe(Side),
	text_layout: vgo.Text_Layout,
	toggled:     bool,
	size:        f32,
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
	info.size = core.style.visual_size.y * 0.8
	if len(info.text) > 0 {
		info.text_layout = vgo.make_text_layout(
			info.text,
			core.style.default_font,
			core.style.default_text_size,
		)
		if info.text_side == .Bottom || info.text_side == .Top {
			info.desired_size.x = max(info.size, info.text_layout.size.x)
			info.desired_size.y = info.size + info.text_layout.size.y
		} else {
			info.desired_size.x =
				info.size + info.text_layout.size.x + core.style.text_padding.x * 2
			info.desired_size.y = info.size
		}
	} else {
		info.desired_size = info.size
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
				icon_box = {self.box.lo, info.size}
			case .Right:
				icon_box = {{self.box.hi.x - info.size, self.box.lo.y}, info.size}
			case .Top:
				icon_box = {
					{box_center_x(self.box) - info.size / 2, self.box.hi.y - info.size},
					info.size,
				}
			case .Bottom:
				icon_box = {{box_center_x(self.box) - info.size / 2, self.box.lo.y}, info.size}
			}
			icon_box.lo = linalg.floor(icon_box.lo)
			icon_box.hi += icon_box.lo
		} else {
			icon_box = self.box
		}
		if self.hover_time > 0 {
			vgo.fill_box(
				self.box,
				core.style.rounding,
				vgo.fade(core.style.color.substance, 0.25 * self.hover_time),
			)
		}
		opacity: f32 = 0.5 if self.disabled else 1
		vgo.fill_box(
			icon_box,
			core.style.rounding,
			vgo.fade(core.style.color.accent if state^ else core.style.color.field, opacity),
		)
		center := box_center(icon_box)
		// Paint icon
		if state^ {
			vgo.check(center, info.size / 4, core.style.color.field)
		}
		// Paint text
		text_pos: [2]f32
		if len(info.text) > 0 {
			switch info.text_side {
			case .Left:
				text_pos = {icon_box.hi.x + core.style.text_padding.x, center.y}
			case .Right:
				text_pos = {icon_box.lo.x - core.style.text_padding.x, center.y}
			case .Top:
				text_pos = self.box.lo
			case .Bottom:
				text_pos = {self.box.lo.x, self.box.hi.y}
			}
			vgo.fill_text_layout_aligned(
				info.text_layout,
				text_pos,
				.Left,
				.Center,
				vgo.fade(core.style.color.content, opacity),
			)
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
	info.size = core.style.visual_size.y * 0.75
	desired_size = [2]f32{2, 1} * info.size
	if len(text) > 0 {
		text_layout = vgo.make_text_layout(
			text,
			core.style.default_font,
			core.style.default_text_size,
		)
		desired_size.x += text_layout.size.x + core.style.text_padding.x
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

	variant.state_time = animate(variant.state_time, 0.25, info.state^)
	how_on := ease.quadratic_in_out(variant.state_time)

	if self.visible {
		outer_radius := box_height(self.box) / 2
		switch_box: Box = self.box
		switch text_side {
		case .Left:
			switch_box = get_box_cut_right(self.box, info.size * 2)
		case .Right:
			switch_box = get_box_cut_left(self.box, info.size * 2)
		}
		inner_box := shrink_box(switch_box, 2)
		inner_radius := box_height(inner_box) / 2
		lever_center: [2]f32 = {
			inner_box.lo.x +
			inner_radius +
			(box_width(inner_box) - box_height(inner_box)) * how_on,
			box_center_y(inner_box),
		}

		if how_on < 1 {
			vgo.fill_box(switch_box, paint = core.style.color.field, radius = outer_radius)
		}
		vgo.fill_box(
			{switch_box.lo, lever_center + outer_radius},
			paint = vgo.fade(core.style.color.accent, how_on),
			radius = outer_radius,
		)
		vgo.fill_circle(lever_center, inner_radius, vgo.mix(how_on, core.style.color.fg, core.style.color.field))

		switch text_side {
		case .Left:
			vgo.fill_text_layout(
				text_layout,
				{self.box.lo.x, box_center_y(self.box) - text_layout.size.y / 2},
				core.style.color.content,
			)
		case .Right:
			vgo.fill_text_layout(
				text_layout,
				{
					self.box.hi.x - text_layout.size.x,
					box_center_y(self.box) - text_layout.size.y / 2,
				},
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
				icon_box = {self.box.lo, info.size}
			case .Right:
				icon_box = {{self.box.hi.x - info.size, self.box.lo.y}, info.size}
			case .Top:
				icon_box = {
					{box_center_x(self.box) - info.size / 2, self.box.hi.y - info.size},
					info.size,
				}
			case .Bottom:
				icon_box = {{box_center_x(self.box) - info.size / 2, self.box.lo.y}, info.size}
			}
			icon_box.lo = linalg.floor(icon_box.lo)
			icon_box.hi += icon_box.lo
		} else {
			icon_box = self.box
		}
		icon_center := box_center(icon_box)

		if self.hover_time > 0 {
			vgo.fill_box(
				{{self.box.lo.x, self.box.lo.y}, self.box.hi},
				box_height(self.box) / 2,
				paint = vgo.fade(core.style.color.substance, 0.25 * self.hover_time),
			)
		}

		state_time := ease.quadratic_in_out(kind.state_time)
		vgo.fill_circle(
			icon_center,
			info.size / 2,
			vgo.mix(state_time, core.style.color.field, core.style.color.accent),
		)
		if state_time > 0 {
			vgo.fill_circle(
				icon_center,
				(info.size / 2 - 5) * kind.state_time,
				vgo.fade(core.style.color.field, state_time),
			)
		}
		// Paint text
		if len(info.text) > 0 {
			switch info.text_side {
			case .Left:
				vgo.fill_text_layout(
					info.text_layout,
					{
						icon_box.hi.x + core.style.text_padding.x,
						icon_center.y - info.text_layout.size.y / 2,
					},
					core.style.color.content,
				)
			case .Right:
				vgo.fill_text_layout(
					info.text_layout,
					{
						icon_box.lo.x - core.style.text_padding.x,
						icon_center.y - info.text_layout.size.y / 2,
					},
					core.style.color.content,
				)
			case .Top:
				vgo.fill_text_layout(info.text_layout, self.box.lo, core.style.color.content)
			case .Bottom:
				vgo.fill_text_layout(
					info.text_layout,
					{self.box.lo.x, self.box.hi.y - info.text_layout.size.y},
					core.style.color.content,
				)
			}
		}
		if self.disable_time > 0 {
			vgo.fill_box(self.box, paint = vgo.fade(core.style.color.fg, self.disable_time * 0.5))
		}
	}

	if .Clicked in self.state {
		toggled = true
		if state != nil {
			state^ = !state^
		}
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
