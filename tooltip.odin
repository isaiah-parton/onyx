package onyx

import "../vgo"
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

begin_tooltip :: proc(
	size: [2]f32,
	side: Side,
	offset: Maybe(f32),
	origin: union {[2]f32, Box} = nil,
	bounds: Maybe(Box) = nil,
	loc := #caller_location,
) -> bool {
	object := persistent_object(hash(loc))
	begin_object(object) or_return

	anchor_point: [2]f32

	switch v in origin {
	case [2]f32:
		anchor_point = v
	case Box:
		switch side {
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
		anchor_point = global_state.mouse_pos
	}

	box: Box

	offset := offset.? or_else DEFAULT_TOOLTIP_OFFSET

	switch side {
	case .Top:
		box = {
			{anchor_point.x - size.x / 2, anchor_point.y - size.y - offset},
			{anchor_point.x + size.x / 2, anchor_point.y - offset},
		}
	case .Bottom:
		box = {
			{anchor_point.x - size.x / 2, anchor_point.y + offset},
			{anchor_point.x + size.x / 2, anchor_point.y + size.y * offset},
		}
	case .Left:
		box = {
			{anchor_point.x - size.x - offset, anchor_point.y - size.y / 2},
			{anchor_point.x - offset, anchor_point.y + size.y / 2},
		}
	case .Right:
		box = {
			{anchor_point.x + offset, anchor_point.y - size.y / 2},
			{anchor_point.x + size.x + offset, anchor_point.y + size.y / 2},
		}
	}

	bg_color := global_state.style.color.bg[0]

	draw_shadow(box)
	begin_layer(&{box = box, kind = .Topmost}, loc)
	vgo.fill_box(box, global_state.style.rounding, bg_color)

	#partial switch side {
	case .Top:
		center := box_center_x(box)
		left := box.lo.x + global_state.style.rounding
		right := box.hi.x - global_state.style.rounding
		vgo.begin_path()
		vgo.move_to({center, box.hi.y + offset})
		vgo.quad_bezier_to({center, box.hi.y}, {right, box.hi.y})
		vgo.line_to({left, box.hi.y})
		vgo.quad_bezier_to({center, box.hi.y}, {center, box.hi.y + offset})
		vgo.fill_path(bg_color)
	case .Bottom:
		center := box_center_x(box)
		left := box.lo.x + global_state.style.rounding
		right := box.hi.x - global_state.style.rounding
		vgo.begin_path()
		vgo.move_to({center, box.lo.y - offset})
		vgo.quad_bezier_to({center, box.lo.y}, {right, box.lo.y})
		vgo.line_to({left, box.lo.y})
		vgo.quad_bezier_to({center, box.lo.y}, {center, box.lo.y - offset})
		vgo.fill_path(bg_color)
	case .Right:
		center := box_center_y(box)
		top := box.lo.y + global_state.style.rounding
		bottom := box.hi.y - global_state.style.rounding
	case .Left:
		center := box_center_y(box)
		top := box.lo.y + global_state.style.rounding
		bottom := box.hi.y - global_state.style.rounding
	}

	return true
}

end_tooltip :: proc() {
	end_layer()
	end_object()
}
