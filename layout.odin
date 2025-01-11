package onyx

import "../vgo"
import "base:runtime"
import "core:fmt"
import "core:math"
import "core:math/linalg"

Layout :: struct {
	box:                Box,
	bounds:             Box,
	does_grow:          bool,
	next_cut_side:      Side,
	next_cut_size:      [2]f32,
	next_box_align:     Align,
	content_size:       [2]f32,
	next_corner_radius: [4]f32,
}

Axis :: enum {
	X,
	Y,
}

Align :: enum {
	Near,
	Center,
	Far,
}

current_layout :: proc() -> Maybe(^Layout) {
	if global_state.layout_stack.height > 0 {
		return &global_state.layout_stack.items[global_state.layout_stack.height - 1]
	}
	return nil
}

push_layout :: proc(layout: Layout) -> bool {
	return push_stack(&global_state.layout_stack, layout)
}

pop_layout :: proc() {
	pop_stack(&global_state.layout_stack)
}

next_box :: proc(size: [2]f32, fixed: bool = false) -> Box {
	return next_user_defined_box() or_else next_box_from_current_layout(size, fixed)
}

next_user_defined_box :: proc() -> (box: Box, ok: bool) {
	box, ok = global_state.next_box.?
	if ok {
		global_state.next_box = nil
	}
	return
}

next_box_from_current_layout :: proc(size: [2]f32, fixed: bool) -> Box {
	return next_box_from_layout(current_layout().?, size, fixed)
}

next_box_from_layout :: proc(layout: ^Layout, size: [2]f32, fixed: bool) -> Box {
	i := int(layout.next_cut_side) / 2
	j := 1 - i

	size := size
	if !fixed {
		size = linalg.max(size, layout.next_cut_size)
	}

	if layout.does_grow {
		switch layout.next_cut_side {
		case .Top:
			layout.box.hi.y = max(layout.box.hi.y, layout.box.lo.y + size[i])
		case .Bottom:
		case .Left:
		case .Right:
		}
	}

	box := cut_box(&layout.box, layout.next_cut_side, size[i])

	switch layout.next_box_align {
	case .Near:
		box.hi[j] = box.lo[j] + size[j]
	case .Center:
		baseline := box.hi[j] - box.lo[j]
		box.lo[j] = baseline - size[j] / 2
		box.hi[j] = baseline + size[j] / 2
	case .Far:
		box.lo[j] = box.hi[j] - size[j]
	}

	return snapped_box(box)
}

axis_normal :: proc(axis: Axis) -> [2]f32 {
	return {f32(1 - i32(axis)), f32(i32(axis))}
}

shift_near_edge_of_box :: proc(box: Box, axis: Axis, amount: f32) -> Box {
	box := box
	box.lo[int(axis)] += amount
	return box
}

apply_near_object_margin :: proc(position: [2]f32, axis: Axis, margin: [4]f32) -> [2]f32 {
	position := position
	position[int(axis)] += margin[int(axis)]
	return position
}

apply_far_object_margin :: proc(position: [2]f32, axis: Axis, margin: [4]f32) -> [2]f32 {
	position := position
	position[int(axis)] += margin[2 + int(axis)]
	return position
}

apply_perpendicular_object_margin :: proc(box: Box, axis: Axis, margin: [4]f32) -> Box {
	box := box
	i := 1 - int(axis)
	box.lo[i] += margin[i]
	box.hi[i] -= margin[2 + i]
	return box
}

apply_object_alignment :: proc(box: Box, axis: Axis, align: Align, size: [2]f32) -> Box {
	box := box
	i := 1 - int(axis)

	switch align {
	case .Near:
		box.hi[i] = box.lo[i] + size[i]
	case .Far:
		box.lo[i] = box.hi[i] - size[i]
	case .Center:
		box.lo[i] = (box.lo[i] + box.hi[i]) / 2 - size[i] / 2
		box.hi[i] = box.lo[i] + size[i]
	}

	return box
}

inverse_axis :: proc(axis: Axis) -> Axis {
	return Axis(1 - int(axis))
}

current_axis :: proc() -> Axis {
	if layout, ok := current_layout().?; ok {
		return axis_of_side(layout.next_cut_side)
	}
	return .Y
}

begin_layout :: proc(side: Side, size: [2]f32 = {}, does_grow: bool = false) -> bool {
	box := next_box(size)
	layout := Layout {
		does_grow          = does_grow,
		box                = box,
		bounds             = box,
		next_cut_side      = side,
		next_corner_radius = global_state.style.rounding,
	}
	if parent_layout, ok := current_layout().?; ok {
		layout.next_cut_size = parent_layout.next_cut_size
		layout.next_corner_radius = parent_layout.next_corner_radius
	}
	return push_layout(layout)
}

end_layout :: proc() {
	pop_layout()
}

axis_of_side :: proc(side: Side) -> Axis {
	return Axis(int(side) / 2)
}

axis_cut_side :: proc(axis: Axis) -> Side {
	if axis == .X {
		return .Left
	}
	return .Top
}

shrink :: proc(amount: [4]f32) {
	layout := current_layout().?
	layout.box.lo += amount.xy
	layout.box.hi -= amount.zw
}

space :: proc(amount: f32) {
	layout := current_layout().?
	cut_box(&layout.box, layout.next_cut_side, amount)
}

set_size :: proc(size: f32) {
	current_layout().?.next_cut_size = size
}

set_next_box :: proc(box: Box) {
	global_state.next_box = box
}

set_width :: proc(width: f32) {
	current_layout().?.next_cut_size.x = width
}

set_height :: proc(height: f32) {
	current_layout().?.next_cut_size.y = height
}

remaining_space :: proc() -> [2]f32 {
	layout := current_layout().?
	return layout.box.hi - layout.box.lo
}
