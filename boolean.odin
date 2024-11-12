package onyx

import "../vgo"
import "core:fmt"
import "core:math"
import "core:math/ease"
import "core:math/linalg"

Boolean_Type :: enum {
	Checkbox,
	Radio,
	Switch,
}

Boolean :: struct {
	using base:      ^Object,
	value:           ^bool,
	type:            Boolean_Type,
	animation_timer: f32,
	side:            Side,
	text:            string,
	text_layout:     vgo.Text_Layout,
	gadget_size:       [2]f32,
}

boolean :: proc(
	state: ^bool,
	text: string = "",
	text_side: Side = .Left,
	type: Boolean_Type = .Checkbox,
	loc := #caller_location,
) {
	object := persistent_object(hash(loc))
	if begin_object(object) {
		defer end_object()

		if object.variant == nil {
			object.variant = Boolean {
				base = object,
			}
		}
		boolean := &object.variant.(Boolean)
		boolean.value = state
		boolean.gadget_size = global_state.style.visual_size.y * 0.8
		if type == .Switch do boolean.gadget_size *= [2]f32{2, 1}
		boolean.type = type
		boolean.text = text
		if len(text) > 0 {
			boolean.text_layout = vgo.make_text_layout(
				text,
				global_state.style.default_text_size,
				global_state.style.default_font,
			)
			if int(text_side) > 1 {
				object.desired_size.x = max(boolean.gadget_size.x, boolean.text_layout.size.x)
				object.desired_size.y = boolean.gadget_size.x + boolean.text_layout.size.y
			} else {
				object.desired_size.x =
					boolean.gadget_size.x +
					boolean.text_layout.size.x +
					global_state.style.text_padding.x * 2
				object.desired_size.y = boolean.gadget_size.y
			}
		}
	}
}

display_boolean :: proc(boolean: ^Boolean) {
	handle_object_click(boolean)

	if .Hovered in boolean.state {
		set_cursor(.Pointing_Hand)
	}
	if point_in_box(global_state.mouse_pos, boolean.box) {
		hover_object(boolean)
	}
	boolean.animation_timer = animate(boolean.animation_timer, 0.2, boolean.value^)

	if object_is_visible(boolean) {
		gadget_box: Box

		if len(boolean.text) > 0 {
			switch boolean.side {
			case .Left:
				gadget_box = {boolean.box.lo, boolean.gadget_size}
			case .Right:
				gadget_box = {
					{boolean.box.hi.x - boolean.gadget_size.x, boolean.box.lo.y},
					boolean.gadget_size,
				}
			case .Top:
				gadget_box = {
					{
						box_center_x(boolean.box) - boolean.gadget_size.x / 2,
						boolean.box.hi.y - boolean.gadget_size.y,
					},
					boolean.gadget_size,
				}
			case .Bottom:
				gadget_box = {
					{box_center_x(boolean.box) - boolean.gadget_size.x / 2, boolean.box.lo.y},
					boolean.gadget_size,
				}
			}
			gadget_box.hi += gadget_box.lo
		} else {
			gadget_box = boolean.box
		}

		gadget_center := box_center(gadget_box)

		if .Hovered in boolean.state {
			vgo.fill_box(
				{{gadget_center.x, boolean.box.lo.y}, boolean.box.hi},
				{0, global_state.style.rounding, 0, global_state.style.rounding},
				vgo.fade(colors().substance, 0.2),
			)
		}

		opacity: f32 = 0.5 if boolean.disabled else 1

		state_time := ease.quadratic_in_out(boolean.animation_timer)
		// Paint icon
		switch boolean.type {
		case .Checkbox:
			if state_time < 1 {
				vgo.fill_box(gadget_box, global_state.style.rounding, colors().field)
			}
			if state_time > 0 && state_time < 1 {
				vgo.push_scissor(vgo.make_box(boolean.box, global_state.style.rounding))
			}
			vgo.fill_box(
				gadget_box,
				global_state.style.rounding,
				vgo.fade(colors().accent, state_time),
			)
			if state_time > 0 {
				gadget_box := move_box(
				gadget_box,
					{
						0,
						box_height(gadget_box) *
						((1 - state_time) if boolean.value^ else -(1 - state_time)),
					},
				)
				vgo.check(gadget_center, boolean.gadget_size.y / 4, colors().field)
			}
			if state_time > 0 && state_time < 1 {
				vgo.pop_scissor()
			}
		case .Radio:
			gadget_center := box_center(gadget_box)
			radius := boolean.gadget_size.y / 2
			vgo.fill_circle(
				gadget_center,
				radius,
				vgo.mix(state_time, colors().field, colors().accent),
			)
			if state_time > 0 {
				vgo.fill_circle(
					gadget_center,
					(radius - 5) * state_time,
					vgo.fade(colors().field, state_time),
				)
			}
		case .Switch:
			inner_box := shrink_box(gadget_box, 2)
			outer_radius := box_height(gadget_box) / 2
			inner_radius := box_height(inner_box) / 2
			lever_center: [2]f32 = {
				inner_box.lo.x +
				inner_radius +
				(box_width(inner_box) - box_height(inner_box)) * state_time,
				box_center_y(inner_box),
			}
			if state_time < 1 {
				vgo.fill_box(gadget_box, paint = colors().field, radius = outer_radius)
			}
			vgo.fill_box(
				{gadget_box.lo, lever_center + outer_radius},
				radius = outer_radius,
				paint = vgo.fade(colors().accent, state_time),
			)
			vgo.fill_circle(lever_center, inner_radius, vgo.mix(state_time, colors().fg, colors().field))
		}
		// Paint text
		text_pos: [2]f32
		if len(boolean.text) > 0 {
			switch boolean.side {
			case .Left:
				text_pos = {
					gadget_box.hi.x + global_state.style.text_padding.x,
					box_center_y(boolean.box),
				}
			case .Right:
				text_pos = {
					gadget_box.lo.x - global_state.style.text_padding.x,
					box_center_y(boolean.box),
				}
			case .Top:
				text_pos = boolean.box.lo
			case .Bottom:
				text_pos = {boolean.box.lo.x, boolean.box.hi.y}
			}
			vgo.fill_text_layout(
				boolean.text_layout,
				text_pos,
				align_x = .Left,
				align_y = .Center,
				paint = vgo.fade(colors().content, opacity),
			)
		}
	}

	if .Clicked in boolean.state {
		boolean.value^ = !boolean.value^
	}
}

// checkbox :: proc(info: Boolean, loc := #caller_location) -> Boolean {
// 	info := info
// 	if init_boolean(&info, loc) {
// 		add_checkbox(&info)
// 	}
// 	return info
// }

// Toggle_Switch :: Boolean

// init_toggle_switch :: proc(using info: ^Toggle_Switch, loc := #caller_location) -> bool {
// 	text_side = text_side.? or_else .Right
// 	info.size = core.style.visual_size.y * 0.75
// 	id = hash(loc)
// 	self = get_object(id)
// 	object.desired_size = [2]f32{2, 1} * info.size
// 	if len(text) > 0 {
// 		text_layout = vgo.make_text_layout(
// 			text,
// 			core.style.default_font,
// 			core.style.default_text_size,
// 		)
// 		self.desired_size.x += text_layout.size.x + core.style.text_padding.x * 2
// 	}
// 	fixed_size = true
// 	return true
// }

// add_toggle_switch :: proc(using info: ^Toggle_Switch) -> bool {
// 	begin_object(info) or_return
// 	defer end_object()

// 	variant := object_kind(self, Boolean_Kind)

// 	button_behavior(self)

// 	variant.state_time = animate(variant.state_time, 0.25, info.state^)
// 	how_on := ease.quadratic_in_out(variant.state_time)

// 	if self.visible {
// 		outer_radius := box_height(self.box) / 2
// 		switch_box: Box = self.box
// 		switch text_side {
// 		case .Left:
// 			switch_box = get_box_cut_right(self.box, info.size * 2)
// 		case .Right:
// 			switch_box = get_box_cut_left(self.box, info.size * 2)
// 		}
// 		inner_box := shrink_box(switch_box, 2)
// 		inner_radius := box_height(inner_box) / 2
// 		lever_center: [2]f32 = {
// 			inner_box.lo.x +
// 			inner_radius +
// 			(box_width(inner_box) - box_height(inner_box)) * how_on,
// 			box_center_y(inner_box),
// 		}

// 		if .Hovered in self.state {
// 			vgo.fill_box(
// 				self.box,
// 				outer_radius,
// 				vgo.fade(colors().substance, 0.2),
// 			)
// 		}

//

// 		switch text_side {
// 		case .Left:
// 			vgo.fill_text_layout(
// 				text_layout,
// 				{self.box.lo.x, box_center_y(self.box) - text_layout.size.y / 2},
// 				colors().content,
// 			)
// 		case .Right:
// 			vgo.fill_text_layout(
// 				text_layout,
// 				{
// 					switch_box.hi.x + core.style.text_padding.x,
// 					box_center_y(self.box) - text_layout.size.y / 2,
// 				},
// 				colors().content,
// 			)
// 		}
// 	}

// 	if .Clicked in self.state {
// 		state^ = !state^
// 		toggled = true
// 	}

// 	return true
// }

// toggle_switch :: proc(info: Toggle_Switch, loc := #caller_location) -> Toggle_Switch {
// 	info := info
// 	if init_toggle_switch(&info, loc) {
// 		add_toggle_switch(&info)
// 	}
// 	return info
// }

// Radio_Button :: Boolean

// add_radio_button :: proc(using info: ^Radio_Button) -> bool {
// 	begin_object(info) or_return
// 	defer end_object()

// 	kind := object_kind(self, Boolean_Kind)
// 	kind.state_time = animate(kind.state_time, 0.15, info.state^)

// 	button_behavior(self)

// 	if self.visible {
// 		gadget_box: Box
// 		if len(info.text) > 0 {
// 			switch info.text_side {
// 			case .Left:
// 				gadget_box = {self.box.lo, info.size}
// 			case .Right:
// 				gadget_box = {{self.box.hi.x - info.size, self.box.lo.y}, info.size}
// 			case .Top:
// 				gadget_box = {
// 					{box_center_x(self.box) - info.size / 2, self.box.hi.y - info.size},
// 					info.size,
// 				}
// 			case .Bottom:
// 				gadget_box = {{box_center_x(self.box) - info.size / 2, self.box.lo.y}, info.size}
// 			}
// 			gadget_box.lo = linalg.floor(gadget_box.lo)
// 			gadget_box.hi += gadget_box.lo
// 		} else {
// 			gadget_box = self.box
// 		}
// 		icon_center := box_center(gadget_box)

// 		if .Hovered in self.state {
// 			vgo.fill_box(
// 				{{self.box.lo.x, self.box.lo.y}, self.box.hi},
// 				box_height(self.box) / 2,
// 				paint = vgo.fade(colors().substance, 0.2),
// 			)
// 		}

//
// 		// Paint text
// 		if len(info.text) > 0 {
// 			switch info.text_side {
// 			case .Left:
// 				vgo.fill_text_layout(
// 					info.text_layout,
// 					{
// 						gadget_box.hi.x + core.style.text_padding.x,
// 						icon_center.y - info.text_layout.size.y / 2,
// 					},
// 					colors().content,
// 				)
// 			case .Right:
// 				vgo.fill_text_layout(
// 					info.text_layout,
// 					{
// 						gadget_box.lo.x - core.style.text_padding.x,
// 						icon_center.y - info.text_layout.size.y / 2,
// 					},
// 					colors().content,
// 				)
// 			case .Top:
// 				vgo.fill_text_layout(info.text_layout, self.box.lo, colors().content)
// 			case .Bottom:
// 				vgo.fill_text_layout(
// 					info.text_layout,
// 					{self.box.lo.x, self.box.hi.y - info.text_layout.size.y},
// 					colors().content,
// 				)
// 			}
// 		}
// 		if self.disable_time > 0 {
// 			vgo.fill_box(self.box, paint = vgo.fade(colors().fg, self.disable_time * 0.5))
// 		}
// 	}

// 	if .Clicked in self.state {
// 		toggled = true
// 		if state != nil {
// 			state^ = !state^
// 		}
// 	}

// 	return true
// }

// radio_button :: proc(info: Radio_Button, loc := #caller_location) -> Radio_Button {
// 	info := info
// 	if init_boolean(&info, loc) {
// 		add_radio_button(&info)
// 	}
// 	return info
// }
