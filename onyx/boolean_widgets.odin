package onyx

import "core:math"
import "core:math/ease"
import "core:math/linalg"

@(private = "file")
SIZE :: 20
@(private = "file")
TEXT_PADDING :: 5

Generic_Boolean_Widget_Info :: struct {
	using generic: Generic_Widget_Info,
	state:         bool,
	text:          string,
	text_side:     Maybe(Side),
	__text_job:    Text_Job,
}

Generic_Boolean_Widget_Kind :: struct {
	state_time: f32,
}

Switch_Info :: struct {
	using _: Generic_Widget_Info,
	on:      bool,
}

Switch_Result :: struct {
	using _: Generic_Widget_Result,
	on:      bool,
}

do_generic_boolean_widget_behavior :: proc(
	widget: ^Widget,
	info: Generic_Boolean_Widget_Info,
) -> ^Generic_Boolean_Widget_Kind {
	kind := widget_kind(widget, Generic_Boolean_Widget_Kind)
	kind.state_time = animate(kind.state_time, 0.15, info.state)
	return kind
}

make_generic_boolean_widget :: proc(
	info: Generic_Boolean_Widget_Info,
	loc := #caller_location,
) -> Generic_Boolean_Widget_Info {
	info := info
	info.id = hash(loc)
	info.text_side = info.text_side.? or_else .Left
	if len(info.text) > 0 {
		if text_job, ok := make_text_job(
			{font = core.style.fonts[.Regular], size = 18, text = info.text},
		); ok {
			info.__text_job = text_job
			if info.text_side == .Bottom || info.text_side == .Top {
				info.desired_size.x = max(SIZE, info.__text_job.size.x)
				info.desired_size.y = SIZE + info.__text_job.size.y
			} else {
				info.desired_size.x = SIZE + info.__text_job.size.x + TEXT_PADDING * 2
				info.desired_size.y = SIZE
			}
		}
	} else {
		info.desired_size = SIZE
	}
	info.fixed_size = true
	return info
}

add_checkbox :: proc(info: Generic_Boolean_Widget_Info) -> (result: Generic_Widget_Result) {
	widget, ok := begin_widget(info)
	if !ok do return

	result.self = widget

	button_behavior(widget)

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
		if widget.hover_time > 0 {
			draw_rounded_box_fill(
				widget.box,
				core.style.rounding,
				fade(core.style.color.substance, 0.5 * widget.hover_time),
			)
		}
		opacity: f32 = 0.5 if widget.disabled else 1
		draw_rounded_box_fill(
			icon_box,
			core.style.rounding,
			fade(core.style.color.accent if info.state else core.style.color.substance, opacity),
		)
		center := box_center(icon_box)
		// Paint icon
		if info.state {
			draw_check(center, SIZE / 4, core.style.color.background)
		}
		// Paint text
		if len(info.text) > 0 {
			switch info.text_side {
			case .Left:
				draw_text_glyphs(
					info.__text_job,
					{icon_box.hi.x + TEXT_PADDING, center.y - info.__text_job.size.y / 2},
					fade(core.style.color.content, opacity),
				)
			case .Right:
				draw_text_glyphs(
					info.__text_job,
					{icon_box.lo.x - TEXT_PADDING, center.y - info.__text_job.size.y / 2},
					fade(core.style.color.content, opacity),
				)
			case .Top:
				draw_text_glyphs(
					info.__text_job,
					widget.box.lo,
					fade(core.style.color.content, opacity),
				)
			case .Bottom:
				draw_text_glyphs(
					info.__text_job,
					{widget.box.lo.x, widget.box.hi.y - info.__text_job.size.y},
					fade(core.style.color.content, opacity),
				)
			}
		}
	}
	end_widget()
	return
}

do_checkbox :: proc(
	info: Generic_Boolean_Widget_Info,
	loc := #caller_location,
) -> Generic_Widget_Result {
	return add_checkbox(make_generic_boolean_widget(info, loc))
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
	variant := widget_kind(widget, Generic_Boolean_Widget_Kind)

	button_behavior(widget)

	variant.state_time = animate(variant.state_time, 0.2, info.on)
	how_on := ease.cubic_in_out(variant.state_time)

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
			interpolate_colors(how_on, core.style.color.substance, core.style.color.accent),
		)
		draw_arc_fill(lever_center, inner_radius, 0, math.TAU, core.style.color.background)


	}

	if .Clicked in widget.state {
		result.on = !result.on
	}

	end_widget()
	return
}

do_switch :: proc(info: Switch_Info, loc := #caller_location) -> Switch_Result {
	return add_switch(make_switch(info, loc))
}

Radio_Button_Info :: Generic_Boolean_Widget_Info

make_radio_button :: proc(info: Radio_Button_Info, loc := #caller_location) -> Radio_Button_Info {
	return make_generic_boolean_widget(info, loc)
}

add_radio_button :: proc(info: Radio_Button_Info) -> (result: Generic_Widget_Result) {
	widget, ok := begin_widget(info)
	if !ok do return
	result.self = widget

	kind := widget_kind(widget, Generic_Boolean_Widget_Kind)
	kind.state_time = animate(kind.state_time, 0.15, info.state)

	button_behavior(widget)

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
		icon_center := box_center(icon_box)

		state_time := ease.circular_in_out(kind.state_time)
		draw_arc_fill(
			icon_center,
			SIZE / 2,
			0,
			math.TAU,
			interpolate_colors(state_time, core.style.color.substance, core.style.color.accent),
		)
		if state_time > 0 {
			draw_arc_fill(
				icon_center,
				(SIZE / 2 - 5) * kind.state_time,
				0,
				math.TAU,
				fade(core.style.color.background, state_time),
			)
		}
		// Paint text
		if len(info.text) > 0 {
			switch info.text_side {
			case .Left:
				draw_text_glyphs(
					info.__text_job,
					{icon_box.hi.x + TEXT_PADDING, icon_center.y - info.__text_job.size.y / 2},
					core.style.color.content,
				)
			case .Right:
				draw_text_glyphs(
					info.__text_job,
					{icon_box.lo.x - TEXT_PADDING, icon_center.y - info.__text_job.size.y / 2},
					core.style.color.content,
				)
			case .Top:
				draw_text_glyphs(info.__text_job, widget.box.lo, core.style.color.content)
			case .Bottom:
				draw_text_glyphs(
					info.__text_job,
					{widget.box.lo.x, widget.box.hi.y - info.__text_job.size.y},
					core.style.color.content,
				)
			}
		}
		if widget.disable_time > 0 {
			draw_box_fill(widget.box, fade(core.style.color.foreground, widget.disable_time * 0.5))
		}
	}

	end_widget()
	return
}

do_radio_button :: proc(
	info: Radio_Button_Info,
	loc := #caller_location,
) -> Generic_Widget_Result {
	return add_radio_button(make_radio_button(info, loc))
}
