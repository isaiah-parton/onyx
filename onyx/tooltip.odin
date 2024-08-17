package onyx

import "core:fmt"
import "core:math"
import "core:math/linalg"

TOOLTIP_OFFSET :: 10

Tooltip_Info :: struct {
	bounds: Box,
	size:   [2]f32,
	time:   f32,
}

Widget_Variant_Tooltip :: struct {
	origin: [2]f32,
	exists: bool,
}

begin_tooltip :: proc(info: Tooltip_Info, loc := #caller_location) -> bool {
	widget, ok := get_widget({id = hash(loc)})
	if !ok do return false

	variant := widget_variant(widget, Widget_Variant_Tooltip)

	bounds := info.bounds if info.bounds != {} else view_box()
	origin: [2]f32 = core.mouse_pos + TOOLTIP_OFFSET
	if origin.x + info.size.x > bounds.hi.x {
		origin.x -= info.size.x + TOOLTIP_OFFSET * 2
	}
	if origin.y + info.size.y > bounds.hi.y {
		origin.y -= info.size.y + TOOLTIP_OFFSET * 2
	}
	origin = linalg.clamp(origin, bounds.lo, bounds.hi - info.size)
	if !variant.exists {
		variant.exists = true
		variant.origin = origin
	}
	box: Box = {linalg.floor(variant.origin), linalg.floor(variant.origin + info.size)}

	diff := (origin - variant.origin)
	if abs(diff.x) >= 0.1 || abs(diff.y) >= 0.1 {
		variant.origin += diff * 7 * core.delta_time
		core.draw_next_frame = true
	}

	begin_layer(
		{
			box     = box,
			// parent = current_layer(),
			options = {.Ghost},
			// origin = box_center(box),
			// scale = [2]f32{1, info.time},
			// rotation = diff.x * 0.001,
		},
		loc,
	)
	draw_rounded_box_fill(box, core.style.rounding, core.style.color.background)

	return true
}

end_tooltip :: proc() {
	draw_rounded_box_stroke(
		current_layer().?.box,
		core.style.rounding,
		1,
		core.style.color.substance,
	)
	end_layer()
}

@(deferred_out = __do_tooltip)
do_tooltip :: proc(info: Tooltip_Info, loc := #caller_location) -> (ok: bool) {
	return begin_tooltip(info, loc)
}

@(private)
__do_tooltip :: proc(ok: bool) {
	if ok {
		end_tooltip()
	}
}
