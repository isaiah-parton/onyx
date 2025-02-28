package ronin

import kn "local:katana"
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
	animation_timer: f32,
}

Boolean_Result :: struct {
	changed: bool,
}

boolean :: proc(
	value: ^bool,
	text: string = "",
	text_side: Side = .Left,
	type: Boolean_Type = .Checkbox,
	loc := #caller_location,
) -> (result: Boolean_Result) {
	self := get_object(hash(loc))
	if self.variant == nil {
		self.variant = Boolean{}
	}
	extras := &self.variant.(Boolean)
	style := get_current_style()

	gadget_size: [2]f32
	base_size := style.scale * golden_ratio

	switch type {
	case .Checkbox, .Radio:
		gadget_size = base_size
	case .Switch:
		gadget_size = [2]f32{golden_ratio, 1} * base_size
	}

	text_layout: kn.Text
	if len(text) > 0 {
		text_layout = kn.make_text(
			text,
			style.default_text_size,
			style.default_font,
		)
		if int(text_side) > 1 {
			self.size.x = max(gadget_size.x, text_layout.size.x)
			self.size.y = gadget_size.x + text_layout.size.y
		} else {
			self.size.x =
				gadget_size.x +
				text_layout.size.x +
				style.text_padding.x * 2
			self.size.y = gadget_size.y
		}
	} else {
		self.size = base_size
	}

	self.size_is_fixed = true

	if do_object(self) {
		if .Hovered in self.state.current {
			set_cursor(.Pointing_Hand)
		}
		if point_in_box(global_state.mouse_pos, self.box) {
			hover_object(self)
		}
		extras.animation_timer = animate(extras.animation_timer, 0.2, value^)

		if object_is_visible(self) {
			gadget_center: [2]f32

			if len(text) > 0 {
				switch text_side {
				case .Left:
					gadget_center = self.box.lo + box_height(self.box) / 2
				case .Right:
					gadget_center = self.box.hi - box_height(self.box) / 2
				case .Top:
					gadget_center = {box_center_x(self.box), self.box.lo.y + gadget_size.y / 2}
				case .Bottom:
					gadget_center = {box_center_x(self.box), self.box.hi.y - gadget_size.y / 2}
				}
			} else {
				gadget_center = box_center(self.box)
			}

			gadget_box := Box{gadget_center - gadget_size / 2, gadget_center + gadget_size / 2}

			if .Hovered in self.state.current {
				kn.add_box(
					self.box,
					style.rounding,
					kn.fade(style.color.button, 0.2),
				)
			}

			opacity: f32 = 0.5 if self.disabled else 1

			state_time := ease.quadratic_in_out(extras.animation_timer)
			gadget_fill_color := style.color.accent
			gadget_accent_color := kn.mix(0.4, gadget_fill_color, kn.Black)

			switch type {
			case .Checkbox:
				kn.add_box(gadget_box, style.rounding, style.color.background)
				if state_time > 0 && state_time < 1 {
					kn.push_scissor(kn.make_box(gadget_box, style.rounding))
				}
				if state_time > 0 {
					gadget_center += {
						0,
						box_height(gadget_box) *
						((1 - state_time) if value^ else -(1 - state_time)),
					}
					kn.add_check(gadget_center, gadget_size.y / 4, style.line_width, style.color.content)
				}
				if state_time > 0 && state_time < 1 {
					kn.pop_scissor()
				}
				kn.add_box_lines(gadget_box, style.line_width, style.rounding, style.color.lines)
			case .Radio:
				gadget_center := box_center(gadget_box)
				radius := gadget_size.y / 2
				kn.add_circle(
					gadget_center,
					radius,
					style.color.foreground,
				)
				kn.add_circle_lines(
					gadget_center,
					radius,
					style.line_width,
					style.color.lines,
				)
				if state_time > 0 {
					kn.add_circle(
						gadget_center,
						(radius - 5) * state_time,
						kn.fade(style.color.content, state_time),
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
				kn.add_box(gadget_box, paint = style.color.button_background, radius = outer_radius)
				kn.add_box_lines(gadget_box, style.line_width, paint = style.color.lines, radius = outer_radius)
				kn.add_circle(
					lever_center,
					inner_radius,
					kn.mix(state_time, style.color.button, style.color.content),
				)
			}

			text_pos: [2]f32
			if len(text) > 0 {
				switch text_side {
				case .Left:
					text_pos = {
						gadget_box.hi.x + style.text_padding.x,
						box_center_y(self.box),
					}
				case .Right:
					text_pos = {
						gadget_box.lo.x - style.text_padding.x,
						box_center_y(self.box),
					}
				case .Top:
					text_pos = self.box.lo
				case .Bottom:
					text_pos = {self.box.lo.x, self.box.hi.y}
				}
				kn.add_text(
					text_layout,
					text_pos - text_layout.size * {0, 0.5},
					paint = kn.fade(style.color.content, opacity),
				)
			}
		}

		if .Clicked in self.state.current {
			value^ = !value^
			result.changed = true
		}
	}
	return
}
