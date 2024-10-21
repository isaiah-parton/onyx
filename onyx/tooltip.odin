package onyx

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

	background_color := fade(core.style.color.background, 0.9125)

	draw_shadow(box, core.style.rounding)
	begin_layer(&{box = box, kind = .Topmost, options = {.No_Scissor}}, loc)
	draw_rounded_box_fill(box, core.style.rounding, background_color)

	// Draw arrow thingy
	start := u32(len(core.gfx.cvs.data))
	#partial switch info.side {
	case .Top:
		center := box_center_x(box)
		left := box.lo.x
		right := box.hi.x
		append(
			&core.gfx.cvs.data,
			[2]f32{right, box.hi.y},
			[2]f32{center, box.hi.y},
			[2]f32{left, box.hi.y},
			[2]f32{left, box.hi.y},
			[2]f32{center, box.hi.y},
			[2]f32{center, box.hi.y + offset},
			[2]f32{center, box.hi.y + offset},
			[2]f32{center, box.hi.y},
			[2]f32{right, box.hi.y},
		)
	case .Bottom:
		center := box_center_x(box)
		left := box.lo.x
		right := box.hi.x
		append(
			&core.gfx.cvs.data,
			[2]f32{right, box.lo.y},
			[2]f32{center, box.lo.y},
			[2]f32{left, box.lo.y},
			[2]f32{left, box.lo.y},
			[2]f32{center, box.lo.y},
			[2]f32{center, box.lo.y - offset},
			[2]f32{center, box.lo.y - offset},
			[2]f32{center, box.lo.y},
			[2]f32{right, box.lo.y},
		)
	case .Right:
		center := box_center_y(box)
		top := box.lo.y
		bottom := box.hi.y
		append(
			&core.gfx.cvs.data,
			[2]f32{box.lo.x, bottom},
			[2]f32{box.lo.x, center},
			[2]f32{box.lo.x, top},
			[2]f32{box.lo.x, top},
			[2]f32{box.lo.x, center},
			[2]f32{box.lo.x - offset, center},
			[2]f32{box.lo.x - offset, center},
			[2]f32{box.lo.x, center},
			[2]f32{box.lo.x, bottom},
		)
	case .Left:
		center := box_center_y(box)
		top := box.lo.y
		bottom := box.hi.y
		append(
			&core.gfx.cvs.data,
			[2]f32{box.hi.x, bottom},
			[2]f32{box.hi.x, center},
			[2]f32{box.hi.x, top},
			[2]f32{box.hi.x, top},
			[2]f32{box.hi.x, center},
			[2]f32{box.hi.x + offset, center},
			[2]f32{box.hi.x + offset, center},
			[2]f32{box.hi.x, center},
			[2]f32{box.hi.x, bottom},
		)
	}
	render_shape(add_shape({kind = .Path, start = start, count = 3}), background_color)

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
