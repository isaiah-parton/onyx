package ui

import "core:math"
import "core:math/linalg"

Tooltip_Info :: struct {
	bounds: Box,
	size: [2]f32,
}

Widget_Variant_Tooltip :: struct {
	origin: [2]f32,
}

begin_tooltip :: proc(info: Tooltip_Info, loc := #caller_location) {
	widget := get_widget({id = hash(loc)})
	variant := widget_variant(widget, Widget_Variant_Tooltip)

	bounds := info.bounds if info.bounds != {} else view_box()
	origin: [2]f32 = core.mouse_pos
	if origin.x + info.size.x > bounds.high.x {
		origin.x -= info.size.x
	}
	if origin.y + info.size.y > bounds.high.y {
		origin.y -= info.size.y
	}
	origin = linalg.clamp(origin, bounds.low, bounds.high - info.size)
	variant.origin += (origin - variant.origin) * 3 * core.delta_time
	box: Box = {
		variant.origin,
		variant.origin + info.size,
	}

	begin_layer({
		box = box, 
		order = .Floating,
	}, loc)
	draw_rounded_box_fill(box, core.style.rounding, core.style.color.background)
}

end_tooltip :: proc() {
	draw_rounded_box_stroke(current_layer().box, core.style.rounding, 1, core.style.color.substance)
	end_layer()
}