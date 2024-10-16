package onyx

import "core:fmt"
import "core:math"
import "core:math/linalg"

TOOLTIP_OFFSET :: 10

Tooltip_Info :: struct {
	bounds: Box,
	pos:    Maybe([2]f32),
	size:   [2]f32,
	time:   f32,
}

Tooltip_Widget_Kind :: struct {
	origin: [2]f32,
	exists: bool,
}

begin_tooltip :: proc(using info: Tooltip_Info, loc := #caller_location) -> bool {
	info := info
	widget_info := Widget_Info {
		id = hash(loc),
	}
	begin_widget(&widget_info) or_return
	defer end_widget()

	variant := widget_kind(widget_info.self, Tooltip_Widget_Kind)

	if bounds == {} {
		info.bounds = view_box()
	}
	origin: [2]f32 = (info.pos.? or_else core.mouse_pos) + TOOLTIP_OFFSET
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

	draw_shadow(box)
	begin_layer(&{box = box, kind = .Topmost}, loc)
	draw_rounded_box_fill(box, core.style.rounding, fade(core.style.color.background, 0.8))

	return true
}

end_tooltip :: proc() {
	end_layer()
}

@(deferred_out = __tooltip)
tooltip :: proc(info: Tooltip_Info, loc := #caller_location) -> bool {
	return begin_tooltip(info, loc)
}

@(private)
__tooltip :: proc(ok: bool) {
	if ok {
		end_tooltip()
	}
}
