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
	widget := get_object(hash(loc))
	if widget.variant == nil {
		widget.variant = Boolean{}
	}
	extras := &widget.variant.(Boolean)

	gadget_size: [2]f32

	base_size := get_current_style().scale

	switch type {
	case .Checkbox, .Radio:
		gadget_size = base_size
	case .Switch:
		gadget_size = [2]f32{1.75, 1} * base_size
	}

	text_layout: kn.Text
	if len(text) > 0 {
		text_layout = kn.make_text(
			text,
			global_state.style.default_text_size,
			global_state.style.default_font,
		)
		if int(text_side) > 1 {
			widget.size.x = max(gadget_size.x, text_layout.size.x)
			widget.size.y = gadget_size.x + text_layout.size.y
		} else {
			widget.size.x =
				gadget_size.x +
				text_layout.size.x +
				global_state.style.text_padding.x * 2
			widget.size.y = gadget_size.y
		}
	} else {
		widget.size = base_size
	}

	widget.size_is_fixed = true

	if do_object(widget) {
		if .Hovered in widget.state.current {
			set_cursor(.Pointing_Hand)
		}
		if point_in_box(global_state.mouse_pos, widget.box) {
			hover_object(widget)
		}
		extras.animation_timer = animate(extras.animation_timer, 0.2, value^)

		if object_is_visible(widget) {
			gadget_box: Box

			if len(text) > 0 {
				switch text_side {
				case .Left:
					gadget_box = {widget.box.lo, gadget_size}
				case .Right:
					gadget_box = {
						{widget.box.hi.x - gadget_size.x, widget.box.lo.y},
						gadget_size,
					}
				case .Top:
					gadget_box = {
						{
							box_center_x(widget.box) - gadget_size.x / 2,
							widget.box.hi.y - gadget_size.y,
						},
						gadget_size,
					}
				case .Bottom:
					gadget_box = {
						{box_center_x(widget.box) - gadget_size.x / 2, widget.box.lo.y},
						gadget_size,
					}
				}
				gadget_box.hi += gadget_box.lo
			} else {
				gadget_box = widget.box
			}

			gadget_center := box_center(gadget_box)

			if .Hovered in widget.state.current {
				kn.add_box(
					{{gadget_center.x, widget.box.lo.y}, widget.box.hi},
					{0, global_state.style.rounding, 0, global_state.style.rounding},
					kn.fade(get_current_style().color.button, 0.2),
				)
			}

			opacity: f32 = 0.5 if widget.disabled else 1

			state_time := ease.quadratic_in_out(extras.animation_timer)
			gadget_fill_color := get_current_style().color.accent
			gadget_accent_color := kn.mix(0.4, gadget_fill_color, kn.Black)

			switch type {
			case .Checkbox:
				kn.add_box(gadget_box, global_state.style.rounding, get_current_style().color.foreground)
				kn.add_box_lines(gadget_box, 1, global_state.style.rounding, get_current_style().color.lines)
				if state_time > 0 && state_time < 1 {
					kn.push_scissor(kn.make_box(widget.box, global_state.style.rounding))
				}
				if state_time > 0 {
					gadget_center += {
						0,
						box_height(gadget_box) *
						((1 - state_time) if value^ else -(1 - state_time)),
					}
					kn.add_check(gadget_center, gadget_size.y / 4, 1, get_current_style().color.content)
				}
				if state_time > 0 && state_time < 1 {
					kn.pop_scissor()
				}
			case .Radio:
				gadget_center := box_center(gadget_box)
				radius := gadget_size.y / 2
				kn.add_circle(
					gadget_center,
					radius,
					get_current_style().color.foreground,
				)
				kn.add_circle_lines(
					gadget_center,
					radius,
					1,
					get_current_style().color.lines,
				)
				if state_time > 0 {
					kn.add_circle(
						gadget_center,
						(radius - 5) * state_time,
						kn.fade(get_current_style().color.content, state_time),
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
				kn.add_box(gadget_box, paint = get_current_style().color.button_background, radius = outer_radius)
				kn.add_box_lines(gadget_box, 1, paint = get_current_style().color.lines, radius = outer_radius)
				kn.add_circle(
					lever_center,
					inner_radius,
					kn.mix(state_time, get_current_style().color.button, get_current_style().color.content),
				)
			}

			text_pos: [2]f32
			if len(text) > 0 {
				switch text_side {
				case .Left:
					text_pos = {
						gadget_box.hi.x + global_state.style.text_padding.x,
						box_center_y(widget.box),
					}
				case .Right:
					text_pos = {
						gadget_box.lo.x - global_state.style.text_padding.x,
						box_center_y(widget.box),
					}
				case .Top:
					text_pos = widget.box.lo
				case .Bottom:
					text_pos = {widget.box.lo.x, widget.box.hi.y}
				}
				kn.add_text(
					text_layout,
					text_pos - text_layout.size * {0, 0.5},
					paint = kn.fade(get_current_style().color.content, opacity),
				)
			}
		}

		if .Clicked in widget.state.current {
			value^ = !value^
			result.changed = true
		}
	}
	return
}
