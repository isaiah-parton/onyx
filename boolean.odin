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
	gadget_size:     [2]f32,
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

display_boolean :: proc(self: ^Boolean) {
	apply_layout_placement(self)
	handle_object_click(self)

	if .Hovered in self.state {
		set_cursor(.Pointing_Hand)
	}
	if point_in_box(global_state.mouse_pos, self.box) {
		hover_object(self)
	}
	self.animation_timer = animate(self.animation_timer, 0.2, self.value^)

	if object_is_visible(self) {
		gadget_box: Box

		if len(self.text) > 0 {
			switch self.side {
			case .Left:
				gadget_box = {self.box.lo, self.gadget_size}
			case .Right:
				gadget_box = {
					{self.box.hi.x - self.gadget_size.x, self.box.lo.y},
					self.gadget_size,
				}
			case .Top:
				gadget_box = {
					{
						box_center_x(self.box) - self.gadget_size.x / 2,
						self.box.hi.y - self.gadget_size.y,
					},
					self.gadget_size,
				}
			case .Bottom:
				gadget_box = {
					{box_center_x(self.box) - self.gadget_size.x / 2, self.box.lo.y},
					self.gadget_size,
				}
			}
			gadget_box.hi += gadget_box.lo
		} else {
			gadget_box = self.box
		}

		gadget_center := box_center(gadget_box)

		if .Hovered in self.state {
			vgo.fill_box(
				{{gadget_center.x, self.box.lo.y}, self.box.hi},
				{0, global_state.style.rounding, 0, global_state.style.rounding},
				vgo.fade(colors().substance, 0.2),
			)
		}

		opacity: f32 = 0.5 if self.disabled else 1

		state_time := ease.quadratic_in_out(self.animation_timer)

		switch self.type {
		case .Checkbox:
			if state_time < 1 {
				vgo.fill_box(gadget_box, global_state.style.rounding, colors().field)
			}
			if state_time > 0 && state_time < 1 {
				vgo.push_scissor(vgo.make_box(self.box, global_state.style.rounding))
			}
			vgo.fill_box(
				gadget_box,
				global_state.style.rounding,
				vgo.fade(colors().accent, state_time),
			)
			if state_time > 0 {
				gadget_center += {
					0,
					box_height(gadget_box) *
					((1 - state_time) if self.value^ else -(1 - state_time)),
				}
				vgo.check(gadget_center, self.gadget_size.y / 4, colors().field)
			}
			if state_time > 0 && state_time < 1 {
				vgo.pop_scissor()
			}
		case .Radio:
			gadget_center := box_center(gadget_box)
			radius := self.gadget_size.y / 2
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
			vgo.fill_circle(
				lever_center,
				inner_radius,
				vgo.mix(state_time, colors().fg, colors().field),
			)
		}
		// Paint text
		text_pos: [2]f32
		if len(self.text) > 0 {
			switch self.side {
			case .Left:
				text_pos = {
					gadget_box.hi.x + global_state.style.text_padding.x,
					box_center_y(self.box),
				}
			case .Right:
				text_pos = {
					gadget_box.lo.x - global_state.style.text_padding.x,
					box_center_y(self.box),
				}
			case .Top:
				text_pos = self.box.lo
			case .Bottom:
				text_pos = {self.box.lo.x, self.box.hi.y}
			}
			vgo.fill_text_layout(
				self.text_layout,
				text_pos,
				align = {0, 0.5},
				paint = vgo.fade(colors().content, opacity),
			)
		}
	}

	if .Clicked in self.state {
		self.value^ = !self.value^
	}
}
