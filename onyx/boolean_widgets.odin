package onyx

import "core:math"
import "core:math/ease"
import "core:math/linalg"

@(private = "file")
SIZE :: 20
@(private = "file")
TEXT_PADDING :: 5

// Checkboxes and radio buttons are the same thing under the hood

Boolean_Widget_Info :: struct {
	using _:   Widget_Info,
	state:     ^bool,
	text:      string,
	text_side: Maybe(Side),
}

Boolean_Widget :: struct {
	using info: Boolean_Widget_Info,
	state_time: f32,
	hover_time: f32,
	text_job:   Text_Job,
}

boolean_widget_behavior :: proc(widget: ^Widget) {
	assert(widget != nil)
	widget.boolean.state_time = animate(widget.boolean.state_time, 0.15, widget.boolean.state^)
}

make_boolean_widget :: proc(
	info: Boolean_Widget_Info,
	loc := #caller_location,
) -> (
	widget: Boolean_Widget,
	ok: bool,
) {
	// Forbid null pointers (duh)
	if widget.state == nil {
		return
	}
	widget.info = info
	widget.id = hash(loc)
	widget.text_side = widget.text_side.? or_else .Left
	if len(widget.text) > 0 {
		// Precompute text
		widget.text_job = make_text_job(
			{font = core.style.fonts[.Regular], size = 18, text = widget.text},
		) or_return
		// Now account for text alignment
		if widget.text_side == .Bottom || widget.text_side == .Top {
			widget.desired_size.x = max(SIZE, widget.text_job.size.x)
			widget.desired_size.y = SIZE + widget.text_job.size.y
		} else {
			widget.desired_size.x =
				SIZE + widget.text_job.size.x + TEXT_PADDING * 2
			widget.desired_size.y = SIZE
		}
	} else {
		widget.desired_size = SIZE
	}
	widget.fixed_size = true
	return
}

add_checkbox :: proc(widget: Boolean_Widget) -> (ok: bool) {
	begin_widget(widget) or_return

	boolean_widget_behavior(widget.self)

	if widget.self.visible {
		icon_box: Box
		if len(widget.text) > 0 {
			switch widget.text_side {
			case .Left:
				icon_box = {widget.self.box.lo, SIZE}
			case .Right:
				icon_box = {{widget.self.box.hi.x - SIZE, widget.self.box.lo.y}, SIZE}
			case .Top:
				icon_box = {
					{
						box_center_x(widget.self.box) - SIZE / 2,
						widget.self.box.hi.y - SIZE,
					},
					SIZE,
				}
			case .Bottom:
				icon_box = {
					{box_center_x(widget.self.box) - SIZE / 2, widget.self.box.lo.y},
					SIZE,
				}
			}
			icon_box.lo = linalg.floor(icon_box.lo)
			icon_box.hi += icon_box.lo
		} else {
			icon_box = widget.self.box
		}
		if widget.hover_time > 0 {
			draw_rounded_box_fill(
				widget.self.box,
				core.style.rounding,
				fade(core.style.color.substance, 0.5 * widget.hover_time),
			)
		}
		opacity: f32 = 0.5 if widget.disabled else 1
		draw_rounded_box_fill(
			icon_box,
			core.style.rounding,
			fade(
				core.style.color.accent if widget.state^ else core.style.color.substance,
				opacity,
			),
		)
		center := box_center(icon_box)
		// Paint icon
		if widget.state^ {
			draw_check(center, SIZE / 4, core.style.color.background)
		}
		// Paint text
		text_pos: [2]f32
		if len(widget.text) > 0 {
			switch widget.text_side {
			case .Left:
				text_pos = {
					icon_box.hi.x + TEXT_PADDING,
					center.y - widget.text_job.size.y / 2,
				}
			case .Right:
				text_pos = {
					icon_box.lo.x - TEXT_PADDING,
					center.y - widget.text_job.size.y / 2,
				}
			case .Top:
				text_pos = widget.self.box.lo
			case .Bottom:
				text_pos = {
					widget.self.box.lo.x,
					widget.self.box.hi.y - widget.text_job.size.y,
				}
			}
			draw_text_glyphs(
				widget.text_job,
				text_pos,
				fade(core.style.color.content, opacity),
			)
			// if widget.hover_time > 0 {
			// 	draw_box_fill(
			// 		{
			// 			{text_pos.x, text_pos.y + widget.__text_job.ascent + 1},
			// 			{
			// 				text_pos.x + widget.__text_job.size.x,
			// 				text_pos.y + widget.__text_job.ascent + 2,
			// 			},
			// 		},
			// 		fade(core.style.color.content, widget.hover_time),
			// 	)
			// }
		}
	}
	end_widget()
	return true
}

checkbox :: proc(info: Boolean_Widget_Info, loc := #caller_location) -> bool {
	return add_checkbox(make_boolean_widget(info, loc) or_return)
}

Toggle_Switch_Info :: Boolean_Widget_Info

Toggle_Switch :: Boolean_Widget

Toggle_Switch_Result :: Widget_Result

make_toggle_switch :: proc(
	info: Toggle_Switch_Info,
	loc := #caller_location,
) -> (widget: Toggle_Switch, ok: bool) {
	widget.info = info
	widget.id = hash(loc)
	widget.fixed_size = true
	widget.desired_size = {40, 20}
	return
}

add_toggle_switch :: proc(
	widget: Toggle_Switch,
) -> (result: Toggle_Switch_Result, ok: bool) {
	begin_widget(widget) or_return

	boolean_widget_behavior(widget.self)

	if widget.self.visible {
		outer_radius := box_height(widget.self.box) / 2
		inner_box := shrink_box(widget.self.box, 2)
		inner_radius := box_height(inner_box) / 2
		lever_center: [2]f32 = {
			inner_box.lo.x +
			inner_radius +
			(box_width(inner_box) - box_height(inner_box)) * widget.state_time,
			box_center_y(inner_box),
		}

		draw_rounded_box_fill(
			widget.self.box,
			outer_radius,
			interpolate_colors(
				widget.state_time,
				core.style.color.substance,
				core.style.color.accent,
			),
		)
		draw_arc_fill(
			lever_center,
			inner_radius,
			0,
			math.TAU,
			core.style.color.background,
		)
	}

	if .Clicked in widget.self.state {
		assert(widget.self.state != nil)
		widget.state^ = !widget.state^
	}

	end_widget()
	return
}

toggle_switch :: proc(
	info: Toggle_Switch_Info,
	loc := #caller_location,
) -> (result: Toggle_Switch_Result, ok: bool) {
	return add_toggle_switch(make_toggle_switch(info, loc) or_return)
}

Radio_Button_Info :: Boolean_Widget_Info

make_radio_button :: proc(
	info: Radio_Button_Info,
	loc := #caller_location,
) -> (widget: Boolean_Widget, ok: bool) {
	return make_boolean_widget(info, loc)
}

add_radio_button :: proc(
	widget: Radio_Button_Info,
) -> (
	result: Widget_Result,
	ok: bool,
) {
	begin_widget(widget) or_return

	widget.self.boolean.state_time = animate(widget.self.boolean.state_time, 0.15, widget.state^)

	button_behavior(widget.self)

	if widget.self.visible {
		icon_box: Box
		if len(widget.text) > 0 {
			switch widget.text_side {
			case .Left:
				icon_box = {widget.box.lo, SIZE}
			case .Right:
				icon_box = {{widget.box.hi.x - SIZE, widget.box.lo.y}, SIZE}
			case .Top:
				icon_box = {
					{
						box_center_x(widget.box) - SIZE / 2,
						widget.box.hi.y - SIZE,
					},
					SIZE,
				}
			case .Bottom:
				icon_box = {
					{box_center_x(widget.box) - SIZE / 2, widget.box.lo.y},
					SIZE,
				}
			}
			icon_box.lo = linalg.floor(icon_box.lo)
			icon_box.hi += icon_box.lo
		} else {
			icon_box = widget.box
		}
		icon_center := box_center(icon_box)

		if widget.hover_time > 0 {
			draw_box_fill(
				{
					{
						widget.box.lo.x + box_height(widget.box) / 2,
						widget.box.lo.y,
					},
					widget.box.hi,
				},
				fade(core.style.color.substance, 0.5 * widget.hover_time),
			)
		}

		state_time := ease.circular_in_out(widget.state_time)
		draw_arc_fill(
			icon_center,
			SIZE / 2,
			0,
			math.TAU,
			interpolate_colors(
				state_time,
				core.style.color.substance,
				core.style.color.accent,
			),
		)
		if state_time > 0 {
			draw_arc_fill(
				icon_center,
				(SIZE / 2 - 5) * widget.state_time,
				0,
				math.TAU,
				fade(core.style.color.background, state_time),
			)
		}
		// Paint text
		if len(widget.text) > 0 {
			switch widget.text_side {
			case .Left:
				draw_text_glyphs(
					widget.text_job,
					{
						icon_box.hi.x + TEXT_PADDING,
						icon_center.y - widget.text_job.size.y / 2,
					},
					core.style.color.content,
				)
			case .Right:
				draw_text_glyphs(
					widget.text_job,
					{
						icon_box.lo.x - TEXT_PADDING,
						icon_center.y - widget.text_job.size.y / 2,
					},
					core.style.color.content,
				)
			case .Top:
				draw_text_glyphs(
					widget.text_job,
					widget.box.lo,
					core.style.color.content,
				)
			case .Bottom:
				draw_text_glyphs(
					widget.text_job,
					{
						widget.box.lo.x,
						widget.box.hi.y - widget.text_job.size.y,
					},
					core.style.color.content,
				)
			}
		}
		// if widget.disable_time > 0 {
		// 	draw_box_fill(
		// 		widget.box,
		// 		fade(core.style.color.foreground, widget.disable_time * 0.5),
		// 	)
		// }
	}

	end_widget()
	return
}

do_radio_button :: proc(
	info: Radio_Button_Info,
	loc := #caller_location,
) -> (result: Widget_Result, ok: bool) {
	return add_radio_button(make_radio_button(info, loc) or_return)
}
