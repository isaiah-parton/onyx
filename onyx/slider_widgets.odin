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
	info.desired_size = {100, 18}
	info.hi = max(info.hi, info.lo + 1)
	return info
}

add_slider :: proc(info: Slider_Info($T)) -> (result: Slider_Result(T)) {
	widget, ok := get_widget(info)
	if !ok do return
	widget.draggable = true
	widget.box = next_widget_box(info)

	h := box_height(widget.box)

	widget.box.low.y += h / 4
	widget.box.high.y -= h / 4

	radius := box_height(widget.box) / 2
	time := f32(info.value - info.lo) / f32(info.hi - info.lo)
	range_width := box_width(widget.box) - radius * 2

	if widget.visible {
		draw_rounded_box_fill(widget.box, radius, core.style.color.substance)
		draw_rounded_box_fill(
			{widget.box.low, {widget.box.low.x + box_width(widget.box) * time, widget.box.high.y}},
			radius,
			core.style.color.accent,
		)
		draw_arc_fill(
			widget.box.low + radius + {time * range_width, 0},
			h / 2,
			0,
			math.TAU,
			core.style.color.background,
		)
		draw_arc_stroke(
			widget.box.low + radius + {time * range_width, 0},
			h / 2,
			0,
			math.TAU,
			1.5,
			core.style.color.accent,
		)
	}

	if .Pressed in widget.state {
		new_time := clamp((core.mouse_pos.x - widget.box.low.x - radius) / range_width, 0, 1)
		result.value = info.lo + T(new_time * f32(info.hi - info.lo))
		core.draw_next_frame = true
	}

	commit_widget(widget, point_in_box(core.mouse_pos, widget.box))

	return
}

do_slider :: proc(info: Slider_Info($T), loc := #caller_location) -> Slider_Result(T) {
	return add_slider(make_slider(info, loc))
}
