package ui

import "core:intrinsics"
import "core:math"
import "core:math/linalg"

Slider_Info :: struct($T: typeid) where intrinsics.type_is_numeric(T) {
	using _: Generic_Widget_Info,
	value, 
	low,
	high: T,
}

Slider_Result :: struct($T: typeid) {
	using _: Generic_Widget_Result,
	value: Maybe(T),
}

slider :: proc(info: Slider_Info($T), loc := #caller_location) -> (result: Slider_Result(T)) {
	THICKNESS :: 20

	widget := get_widget(info)
	widget.draggable = true
	widget.box = next_widget_box()
	widget.box = align_inner(widget.box, {width(widget.box), THICKNESS}, {.Middle, .Middle})

	widget.box.low = linalg.floor(widget.box.low)
	widget.box.high = linalg.floor(widget.box.high)
		
	widget.box.low.y += THICKNESS / 4
	widget.box.high.y -= THICKNESS / 4

	radius := height(widget.box) / 2
	time := f32(info.value - info.low) / f32(info.high - info.low)
	range_width := width(widget.box) - radius * 2
	draw_rounded_box_fill(widget.box, radius, core.style.color.substance)
	draw_rounded_box_fill({widget.box.low, {widget.box.low.x + width(widget.box) * time, widget.box.high.y}}, radius, core.style.color.content)

	draw_arc_fill(widget.box.low + radius + {time * range_width, 0}, THICKNESS / 2, 0, math.TAU, core.style.color.background)
	draw_arc_stroke(widget.box.low + radius + {time * range_width, 0}, THICKNESS / 2, 0, math.TAU, 1.5, core.style.color.content)

	if .Pressed in widget.state {
		new_time := clamp((core.mouse_pos.x - widget.box.low.x - radius) / range_width, 0, 1)
		result.value = info.low + T(new_time * f32(info.high - info.low))
	}

	commit_widget(widget, point_in_box(core.mouse_pos, widget.box))

	return
}