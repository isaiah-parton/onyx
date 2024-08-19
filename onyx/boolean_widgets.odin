package onyx

import "core:math"
import "core:math/ease"
import "core:math/linalg"

@(private = "file")
SIZE :: 20
@(private = "file")
TEXT_PADDING :: 5

Checkbox_Info :: struct {
	using generic: Generic_Widget_Info,
	value:         bool,
	text:          string,
	text_side:     Maybe(Side),
	__text_size:   [2]f32,
}

Switch_Info :: struct {
	using _: Generic_Widget_Info,
	on:      bool,
}

Switch_Widget_Kind :: struct {
	how_on: f32,
}

Switch_Result :: struct {
	using _: Generic_Widget_Result,
	on:      bool,
}

make_checkbox :: proc(info: Checkbox_Info, loc := #caller_location) -> Checkbox_Info {
	info := info
	info.id = hash(loc)
	info.text_side = info.text_side.? or_else .Left
	if len(info.text) > 0 {
		info.__text_size = measure_text(
			{font = core.style.fonts[.Regular], size = 18, text = info.text},
		)
		if info.text_side == .Bottom || info.text_side == .Top {
			info.desired_size.x = max(SIZE, info.__text_size.x)
			info.desired_size.y = SIZE + info.__text_size.y
		} else {
			info.desired_size.x = SIZE + info.__text_size.x + TEXT_PADDING * 2
			info.desired_size.y = SIZE
		}
	} else {
		info.desired_size = SIZE
	}
	info.fixed_size = true
	return info
}

add_checkbox :: proc(info: Checkbox_Info) -> (result: Generic_Widget_Result) {
	widget, ok := begin_widget(info)
	if !ok do return

	result.self = widget

	if widget.visible {
		icon_box: Box
		if len(info.text) > 0 {
			switch info.text_side {
			case .Left:
				icon_box = {widget.box.lo, SIZE}
			case .Right:
				icon_box = {{widget.box.hi.x - SIZE, widget.box.lo.y}, SIZE}
			case .Top:
				icon_box = {{box_center_x(widget.box) - SIZE / 2, widget.box.hi.y - SIZE}, SIZE}
			case .Bottom:
				icon_box = {{box_center_x(widget.box) - SIZE / 2, widget.box.lo.y}, SIZE}
			}
			icon_box.lo = linalg.floor(icon_box.lo)
			icon_box.hi += icon_box.lo
		} else {
			icon_box = widget.box
		}
		// Hover
		if widget.hover_time > 0 {
			draw_rounded_box_fill(
				widget.box,
				core.style.rounding,
				fade(core.style.color.substance, 0.5 * widget.hover_time),
			)
		}
		// Paint box
		opacity: f32 = 0.5 if widget.disabled else 1
		if info.value {
			draw_rounded_box_fill(
				icon_box,
				core.style.rounding,
				fade(core.style.color.accent, opacity),
			)
		} else {
			draw_rounded_box_stroke(
				icon_box,
				core.style.rounding,
				1,
				fade(core.style.color.accent, opacity),
			)
		}
		center := box_center(icon_box)
		// Paint icon
		if info.value {
			draw_check(center, SIZE / 4, core.style.color.background)
		}
		// Paint text
		if len(info.text) > 0 {
			switch info.text_side {
			case .Left:
				draw_text(
					{icon_box.hi.x + TEXT_PADDING, center.y - info.__text_size.y / 2},
					{text = info.text, font = core.style.fonts[.Regular], size = 18},
					fade(core.style.color.content, opacity),
				)
			case .Right:
				draw_text(
					{icon_box.lo.x - TEXT_PADDING, center.y - info.__text_size.y / 2},
					{
						text = info.text,
						font = core.style.fonts[.Regular],
						size = 18,
						align_h = .Right,
					},
					fade(core.style.color.content, opacity),
				)
			case .Top:
				draw_text(
					widget.box.lo,
					{text = info.text, font = core.style.fonts[.Regular], size = 18},
					fade(core.style.color.content, opacity),
				)
			case .Bottom:
				draw_text(
					{widget.box.lo.x, widget.box.hi.y - info.__text_size.y},
					{text = info.text, font = core.style.fonts[.Regular], size = 18},
					fade(core.style.color.content, opacity),
				)
			}
		}
	}
	button_behavior(widget)
	end_widget()
	return
}

do_checkbox :: proc(info: Checkbox_Info, loc := #caller_location) -> Generic_Widget_Result {
	return add_checkbox(make_checkbox(info, loc))
}

make_switch :: proc(info: Switch_Info, loc := #caller_location) -> Switch_Info {
	info := info
	info.id = hash(loc)
	info.fixed_size = true
	info.desired_size = {40, 20}
	return info
}

add_switch :: proc(info: Switch_Info) -> (result: Switch_Result) {
	widget, ok := begin_widget(info)
	if !ok do return

	result.self = widget
	result.on = info.on
	variant := widget_kind(widget, Switch_Widget_Kind)

	how_on := ease.cubic_in_out(variant.how_on)

	if widget.visible {
		outer_radius := box_height(widget.box) / 2
		inner_box := shrink_box(widget.box, 2)
		inner_radius := box_height(inner_box) / 2
		lever_center: [2]f32 = {
			inner_box.lo.x +
			inner_radius +
			(box_width(inner_box) - box_height(inner_box)) * how_on,
			box_center_y(inner_box),
		}

		draw_rounded_box_fill(
			widget.box,
			outer_radius,
			blend_colors(how_on, core.style.color.substance, core.style.color.accent),
		)
		draw_arc_fill(lever_center, inner_radius, 0, math.TAU, core.style.color.background)
	}

	if .Clicked in widget.state {
		result.on = !result.on
	}

	if .Hovered in widget.state {
		core.cursor_type = .POINTING_HAND
	}

	variant.how_on = animate(variant.how_on, 0.2, info.on)

	if point_in_box(core.mouse_pos, widget.box) {
		widget.try_hover = true
	}

	end_widget()
	return
}

do_switch :: proc(info: Switch_Info, loc := #caller_location) -> Switch_Result {
	return add_switch(make_switch(info, loc))
}
