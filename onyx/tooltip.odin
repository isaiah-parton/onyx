package onyx

import "../../vgo"
import "core:fmt"
import "core:math"
import "core:math/linalg"

DEFAULT_TOOLTIP_OFFSET :: 10

Tooltip_Mode :: enum {
	Floating,
	Snapped,
}

Tooltip_Info :: struct {
	bounds: Box,
	origin: union {
		[2]f32,
		Box,
	},
	offset: Maybe(f32),
	size:   [2]f32,
	side:   Side,
	mode:   Tooltip_Mode,
}

begin_tooltip :: proc(info: Tooltip_Info, loc := #caller_location) -> bool {
	info := info
	widget_info := Widget_Info {
		id  = hash(loc),
		box = Box{},
	}
	begin_widget(&widget_info) or_return
	defer end_widget()

	if info.bounds == {} {
		info.bounds.hi = core.view
	}

	anchor_point: [2]f32

	switch v in info.origin {
	case [2]f32:
		anchor_point = v
	case Box:
		switch info.side {
		case .Top:
			anchor_point = {(v.lo.x + v.hi.x) / 2, v.lo.y}
		case .Bottom:
			anchor_point = {(v.lo.x + v.hi.x) / 2, v.hi.y}
		case .Left:
			anchor_point = {v.lo.x, (v.lo.y + v.hi.y) / 2}
		case .Right:
			anchor_point = {v.hi.x, (v.lo.y + v.hi.y) / 2}
		}
	case:
		anchor_point = core.mouse_pos
	}

	box: Box

	offset := info.offset.? or_else DEFAULT_TOOLTIP_OFFSET

	switch info.side {
	case .Top:
		box = {
			{anchor_point.x - info.size.x / 2, anchor_point.y - info.size.y - offset},
			{anchor_point.x + info.size.x / 2, anchor_point.y - offset},
		}
	case .Bottom:
		box = {
			{anchor_point.x - info.size.x / 2, anchor_point.y + offset},
			{anchor_point.x + info.size.x / 2, anchor_point.y + info.size.y * offset},
		}
	case .Left:
		box = {
			{anchor_point.x - info.size.x - offset, anchor_point.y - info.size.y / 2},
			{anchor_point.x - offset, anchor_point.y + info.size.y / 2},
		}
	case .Right:
		box = {
			{anchor_point.x + offset, anchor_point.y - info.size.y / 2},
			{anchor_point.x + info.size.x + offset, anchor_point.y + info.size.y / 2},
		}
	}

	background_color := core.style.color.background

	draw_shadow(box)
	begin_layer(&{box = box, kind = .Topmost, options = {.No_Scissor}}, loc)
	vgo.fill_box(box, core.style.rounding, background_color)

	#partial switch info.side {
	case .Top:
		center := box_center_x(box)
		left := box.lo.x + core.style.rounding
		right := box.hi.x - core.style.rounding
		vgo.begin_path()
		vgo.move_to({center, box.hi.y + offset})
		vgo.quad_bezier_to({center, box.hi.y}, {right, box.hi.y})
		vgo.line_to({left, box.hi.y})
		vgo.quad_bezier_to({center, box.hi.y}, {center, box.hi.y + offset})
		vgo.fill_path(background_color)
	case .Bottom:
		center := box_center_x(box)
		left := box.lo.x + core.style.rounding
		right := box.hi.x - core.style.rounding
		vgo.begin_path()
		vgo.move_to({center, box.lo.y - offset})
		vgo.quad_bezier_to({center, box.lo.y}, {right, box.lo.y})
		vgo.line_to({left, box.lo.y})
		vgo.quad_bezier_to({center, box.lo.y}, {center, box.lo.y - offset})
		vgo.fill_path(background_color)
	case .Right:
		center := box_center_y(box)
		top := box.lo.y + core.style.rounding
		bottom := box.hi.y - core.style.rounding
	case .Left:
		center := box_center_y(box)
		top := box.lo.y + core.style.rounding
		bottom := box.hi.y - core.style.rounding
	}

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
