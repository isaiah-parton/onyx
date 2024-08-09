package onyx

import "core:math"
import "core:math/ease"

Switch_Info :: struct {
	using _: Generic_Widget_Info,
	on: bool,
}

Switch_Widget_Variant :: struct {
	how_on: f32,
}

Switch_Result :: struct {
	using _: Generic_Widget_Result,
	on: bool,
}

make_switch :: proc(info: Switch_Info, loc := #caller_location) -> Switch_Info {
	info := info
	info.id = hash(loc)
	info.fixed_size = true
	info.desired_size = {
		40,
		20,
	}
	return info
}

add_switch :: proc(info: Switch_Info) -> (result: Switch_Result) {
	widget := get_widget(info)
	widget.box = next_widget_box(info)
	result.self = widget
	result.on = info.on
	variant := widget_variant(widget, Switch_Widget_Variant)

	how_on := ease.cubic_in_out(variant.how_on)

	if widget.visible {
		outer_radius := box_height(widget.box) / 2
		inner_box := shrink_box(widget.box, 2)
		inner_radius := box_height(inner_box) / 2
		lever_center: [2]f32 = {
			inner_box.lo.x + inner_radius + (box_width(inner_box) - box_height(inner_box)) * how_on,
			box_center_y(inner_box),
		}

		draw_rounded_box_fill(widget.box, outer_radius, blend_colors(how_on, core.style.color.substance, core.style.color.accent))
		draw_arc_fill(lever_center, inner_radius, 0, math.TAU, core.style.color.background)
	}

	if .Clicked in widget.state {
		result.on = !result.on
	}

	if .Hovered in widget.state {
		core.cursor_type = .POINTING_HAND
	}

	variant.how_on = animate(variant.how_on, 0.2, info.on)

	commit_widget(widget, point_in_box(core.mouse_pos, widget.box))

	return
}

do_switch :: proc(info: Switch_Info, loc := #caller_location) -> Switch_Result {
	return add_switch(make_switch(info, loc))
}