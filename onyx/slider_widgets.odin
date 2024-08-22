package onyx

import "base:intrinsics"
import "core:math"
import "core:math/linalg"

Slider_Info :: struct($T: typeid) where intrinsics.type_is_numeric(T) {
	using _:       Generic_Widget_Info,
	value, lo, hi: T,
}

Slider_Result :: struct($T: typeid) {
	using _: Generic_Widget_Result,
	value:   Maybe(T),
}

make_slider :: proc(info: Slider_Info($T), loc := #caller_location) -> Slider_Info(T) {
	info := info
	info.id = hash(loc)
	info.desired_size = {100, 20}
	info.hi = max(info.hi, info.lo + 1)
	return info
}

add_slider :: proc(info: Slider_Info($T)) -> (result: Slider_Result(T)) {
	widget, ok := begin_widget(info)
	if !ok do return
	widget.draggable = true
	result.self = widget

	h := box_height(widget.box)

	widget.box.lo.y += h / 4
	widget.box.hi.y -= h / 4

	radius := box_height(widget.box) / 2
	time := f32(info.value - info.lo) / f32(info.hi - info.lo)
	range_width := box_width(widget.box) - radius * 2

	knob_center := widget.box.lo + radius + {time * range_width, 0}
	knob_radius := h / 2

	if widget.visible {
		draw_rounded_box_fill(widget.box, radius, core.style.color.substance)
		draw_rounded_box_fill(
			{widget.box.lo, {widget.box.lo.x + box_width(widget.box) * time, widget.box.hi.y}},
			radius,
			core.style.color.accent,
		)
		draw_arc_fill(knob_center, knob_radius, 0, math.TAU, core.style.color.background)
		draw_arc_stroke(knob_center, knob_radius, 0, math.TAU, 1.5, core.style.color.accent)
	}

	if .Pressed in widget.state {
		new_time := clamp((core.mouse_pos.x - widget.box.lo.x - radius) / range_width, 0, 1)
		result.value = info.lo + T(new_time * f32(info.hi - info.lo))
		core.draw_next_frame = true
	}

	if point_in_box(core.mouse_pos, widget.box) ||
	   linalg.distance(knob_center, core.mouse_pos) <= knob_radius {
		widget.try_hover = true
	}

	end_widget()
	return
}

do_slider :: proc(info: Slider_Info($T), loc := #caller_location) -> Slider_Result(T) {
	return add_slider(make_slider(info, loc))
}
