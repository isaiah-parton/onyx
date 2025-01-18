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
	animation_timer: f32,
}

boolean :: proc(
	value: ^bool,
	text: string = "",
	text_side: Side = .Left,
	type: Boolean_Type = .Checkbox,
	loc := #caller_location,
) {
	object := persistent_object(hash(loc))
	if object.variant == nil {
		object.variant = Boolean{}
	}
	extras := &object.variant.(Boolean)

	gadget_size: [2]f32

	switch type {
	case .Checkbox:
		gadget_size = global_state.style.visual_size.y * 0.8
	case .Radio:
		gadget_size = global_state.style.visual_size.y * 0.8
	case .Switch:
		gadget_size = [2]f32{1.75, 1} * global_state.style.visual_size.y * 0.8
	}

	text_layout: vgo.Text_Layout
	if len(text) > 0 {
		text_layout = vgo.make_text_layout(
			text,
			global_state.style.default_text_size,
			global_state.style.default_font,
		)
		if int(text_side) > 1 {
			object.size.x = max(gadget_size.x, text_layout.size.x)
			object.size.y = gadget_size.x + text_layout.size.y
		} else {
			object.size.x =
				gadget_size.x +
				text_layout.size.x +
				global_state.style.text_padding.x * 2
			object.size.y = gadget_size.y
		}
	}

	if begin_object(object) {
		defer end_object()

		object.box = next_box(object.size, true)

		handle_object_click(object)
		if .Hovered in object.state.current {
			set_cursor(.Pointing_Hand)
		}
		if point_in_box(global_state.mouse_pos, object.box) {
			hover_object(object)
		}
		extras.animation_timer = animate(extras.animation_timer, 0.2, value^)

		if object_is_visible(object) {
			gadget_box: Box

			if len(text) > 0 {
				switch text_side {
				case .Left:
					gadget_box = {object.box.lo, gadget_size}
				case .Right:
					gadget_box = {
						{object.box.hi.x - gadget_size.x, object.box.lo.y},
						gadget_size,
					}
				case .Top:
					gadget_box = {
						{
							box_center_x(object.box) - gadget_size.x / 2,
							object.box.hi.y - gadget_size.y,
						},
						gadget_size,
					}
				case .Bottom:
					gadget_box = {
						{box_center_x(object.box) - gadget_size.x / 2, object.box.lo.y},
						gadget_size,
					}
				}
				gadget_box.hi += gadget_box.lo
			} else {
				gadget_box = object.box
			}

			gadget_center := box_center(gadget_box)

			if .Hovered in object.state.current {
				vgo.fill_box(
					{{gadget_center.x, object.box.lo.y}, object.box.hi},
					{0, global_state.style.rounding, 0, global_state.style.rounding},
					vgo.fade(style().color.substance, 0.2),
				)
			}

			opacity: f32 = 0.5 if object.disabled else 1

			state_time := ease.quadratic_in_out(extras.animation_timer)

			switch type {
			case .Checkbox:
				if state_time < 1 {
					vgo.fill_box(gadget_box, global_state.style.rounding, style().color.field)
				}
				if state_time > 0 && state_time < 1 {
					vgo.push_scissor(vgo.make_box(object.box, global_state.style.rounding))
				}
				vgo.fill_box(
					gadget_box,
					global_state.style.rounding,
					vgo.fade(style().color.accent, state_time),
				)
				if state_time > 0 {
					gadget_center += {
						0,
						box_height(gadget_box) *
						((1 - state_time) if value^ else -(1 - state_time)),
					}
					vgo.fill_box({gadget_center - gadget_size * 0.25, gadget_center + gadget_size * 0.25}, 2, style().color.field)
					// vgo.check(gadget_center, gadget_size.y / 4, style().color.field)
				}
				if state_time > 0 && state_time < 1 {
					vgo.pop_scissor()
				}
			case .Radio:
				gadget_center := box_center(gadget_box)
				radius := gadget_size.y / 2
				vgo.fill_circle(
					gadget_center,
					radius,
					vgo.mix(state_time, style().color.field, style().color.accent),
				)
				if state_time > 0 {
					vgo.fill_circle(
						gadget_center,
						(radius - 5) * state_time,
						vgo.fade(style().color.field, state_time),
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
					vgo.fill_box(gadget_box, paint = style().color.field, radius = outer_radius)
				}
				vgo.fill_box(
					{gadget_box.lo, lever_center + outer_radius},
					radius = outer_radius,
					paint = vgo.fade(style().color.accent, state_time),
				)
				vgo.fill_circle(
					lever_center,
					inner_radius,
					vgo.mix(state_time, style().color.foreground, style().color.field),
				)
			}

			text_pos: [2]f32
			if len(text) > 0 {
				switch text_side {
				case .Left:
					text_pos = {
						gadget_box.hi.x + global_state.style.text_padding.x,
						box_center_y(object.box),
					}
				case .Right:
					text_pos = {
						gadget_box.lo.x - global_state.style.text_padding.x,
						box_center_y(object.box),
					}
				case .Top:
					text_pos = object.box.lo
				case .Bottom:
					text_pos = {object.box.lo.x, object.box.hi.y}
				}
				vgo.fill_text_layout(
					text_layout,
					text_pos,
					align = {0, 0.5},
					paint = vgo.fade(style().color.content, opacity),
				)
			}
		}

		if .Clicked in object.state.current {
			value^ = !value^
		}
	}
}
