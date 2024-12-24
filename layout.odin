package onyx

import "../vgo"
import "base:runtime"
import "core:fmt"
import "core:math"
import "core:math/linalg"

Layout_Content_Placement :: struct {
	axis:   Axis,
	justfy: Align,
	align:  Align,
}

Layout_Metrics :: struct {
	box: Box,
}

Fixed :: distinct f32
At_Least :: distinct f32
Percent :: distinct f32
Percent_Of_Remaining :: distinct f32
At_Most :: distinct f32
Percent_Of_Width :: distinct f32
Percent_Of_Remaining_Width :: distinct f32
Percent_Of_Height :: distinct f32
Percent_Of_Remaining_Height :: distinct f32
Between :: distinct [2]f32

Axis :: enum {
	X,
	Y,
}

Layout_Info :: struct {
	box:         Maybe(Box),
	side:        Maybe(Side),
	size:        Maybe(f32),
	isolated:    bool,
	first_child: int,
	last_child:  int,
}

Align :: enum {
	Near,
	Center,
	Far,
	Equal_Space,
}

Object_Layout_Options :: struct {
	size:   [2]Layout_Size,
	margin: [4]f32,
	align:  Align,
}

axis_normal :: proc(axis: Axis) -> [2]f32 {
	return {f32(1 - i32(axis)), f32(i32(axis))}
}

maybe_defer_object :: proc(object: ^Object) -> bool {
	parent := object.parent.? or_return
	object_defers_children(parent) or_return
	object.is_deferred = true
	append(&parent.children, object)
	return true
}

move_object :: proc(object: ^Object, delta: [2]f32) {
	object.box.lo += delta
	object.box.hi += delta
	for child in object.children {
		move_object(child, delta)
	}
}

shift_near_edge_of_box :: proc(box: Box, axis: Axis, amount: f32) -> Box {
	box := box
	box.lo[int(axis)] += amount
	return box
}

apply_near_object_margin :: proc(box: Box, axis: Axis, margin: [4]f32) -> Box {
	return shift_near_edge_of_box(box, axis, margin[int(axis)])
}

apply_far_object_margin :: proc(box: Box, axis: Axis, margin: [4]f32) -> Box {
	return shift_near_edge_of_box(box, axis, margin[2 + int(axis)])
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
	case .Equal_Space:
	}
	return box
}

place_object :: proc(object: ^Object) -> bool {
	assert(object != nil)

	switch v in object.placement {
	case nil:
		parent := object.parent.? or_return
		object.box = parent.content.box
	case Box:
		object.box = v
	case Future_Box_Placement:
		object.metrics.size = linalg.max(object.metrics.desired_size, object.metrics.size)
		object.box.lo = v.origin - v.align * object.metrics.size
		object.box.hi = object.box.lo + object.metrics.size
	case Child_Placement_Options:
		place_object_in_parent(object, v) or_return
	}

	object.box = snapped_box(object.box)

	object.content.box = solve_object_content_box(object)

	return true
}

solve_object_content_box :: proc(object: ^Object) -> Box {
	return Box {
		object.box.lo + object.content.padding.xy + object.content.offset,
		object.box.hi - object.content.padding.zw + object.content.offset,
	}
}

place_object_in_parent :: proc(object: ^Object, placement: Child_Placement_Options) -> bool {
	assert(object != nil)
	parent := object.parent.? or_return

	content_box := parent.content.box

	object.metrics.size, object.metrics.desired_size = solve_child_object_size(
		placement.size,
		object.metrics.desired_size,
		available_space_for_object_content(parent),
		// FIXME: `parent.metrics.size` is not necessarily valid at this point
		total_space_for_object_content(parent),
	)

	parent_content_axis := axis_of_side(parent.content.side)
	object.box, content_box = split_box(
		apply_near_object_margin(content_box, parent_content_axis, placement.margin),
		parent.content.side,
		object.metrics.size[int(parent_content_axis)],
	)

	content_box = apply_far_object_margin(content_box, parent_content_axis, placement.margin)

	object.box = apply_object_alignment(
		apply_perpendicular_object_margin(object.box, parent_content_axis, placement.margin),
		parent_content_axis,
		placement.align,
		object.metrics.size,
	)

	if parent.content.justify == .Equal_Space {
		content_box.lo[int(parent_content_axis)] +=
		parent.content.space_left[int(parent_content_axis)] / f32(len(parent.children) - 1)
	} else if parent.content.justify == .Center {
		move_object(object, parent.content.space_left * 0.5)
	} else if parent.content.justify == .Far {
		move_object(object, parent.content.space_left)
	}

	parent.content.box = content_box

	return true
}

inverse_axis :: proc(axis: Axis) -> Axis {
	return Axis(1 - int(axis))
}

object_defers_children :: proc(object: ^Object) -> bool {
	return (object.content.justify != .Near) || object.is_deferred
}

object_is_deferred :: proc(object: ^Object) -> bool {
	return object.is_deferred
}

next_user_placement :: proc() -> Child_Placement_Options {
	return current_placement_options()^
}

Future_Box_Placement :: struct {
	origin: [2]f32,
	align:  [2]f32,
}

Layout_Size :: union {
	Fixed,
	At_Least,
	At_Most,
	Between,
	Percent,
	Percent_Of_Remaining,
	Percent_Of_Width,
	Percent_Of_Height,
	Percent_Of_Remaining_Width,
	Percent_Of_Remaining_Height,
}

Object_Placement :: union {
	Box,
	Future_Box_Placement,
	Child_Placement_Options,
}

stack_layout_placement :: proc(axis: Axis, size: Layout_Size) -> Child_Placement_Options {
	placement: Child_Placement_Options
	placement.size[int(axis)] = size
	placement.size[1 - int(axis)] = At_Least(0)
	placement.margin = current_placement_options().margin
	return placement
}

current_axis :: proc() -> Axis {
	if object, ok := current_object().?; ok {
		return axis_of_side(object.content.side)
	}
	return .Y
}

begin_row_layout :: proc(
	size: Layout_Size = nil,
	justify: Align = .Near,
	padding: [4]f32 = 0,
	side: Side = .Left,
) -> bool {
	return begin_layout(
		placement = stack_layout_placement(current_axis(), size),
		justify = justify,
		padding = padding,
		side = side,
	)
}

begin_column_layout :: proc(
	size: Layout_Size = nil,
	justify: Align = .Near,
	padding: [4]f32 = 0,
	side: Side = .Top,
) -> bool {
	return begin_layout(
		placement = stack_layout_placement(current_axis(), size),
		justify = justify,
		padding = padding,
		side = side,
	)
}

begin_layout :: proc(
	placement: Object_Placement = nil,
	justify: Align = .Near,
	padding: [4]f32 = {},
	clip_contents: bool = false,
	isolated: bool = false,
	side: Side = .Left,
) -> bool {
	self := make_transient_object()
	self.state.input_mask = OBJECT_STATE_ALL
	self.content = {
		side    = side,
		justify = justify,
		padding = padding,
	}
	self.isolated = isolated
	self.placement = placement
	self.clip_children = clip_contents

	begin_object(self) or_return
	push_current_placement_options()
	return true
}

end_layout :: proc() {
	pop_placement_options()
	end_object()
}

solve_child_object_size :: proc(
	size: [2]Layout_Size,
	desired_size: [2]f32,
	available_space: [2]f32,
	total_space: [2]f32,
) -> (
	actual_size: [2]f32,
	new_desired_size: [2]f32,
) {
	for i in 0 ..= 1 {
		switch size in size[i] {
		case Percent_Of_Remaining:
			actual_size[i] = available_space[i] * f32(size) * 0.01
		case Percent:
			actual_size[i] = total_space[i] * f32(size) * 0.01
		case Percent_Of_Width:
			actual_size[i] = total_space.x * f32(size) * 0.01
		case Percent_Of_Remaining_Width:
			actual_size[i] = available_space.x * f32(size) * 0.01
		case Percent_Of_Height:
			actual_size[i] = total_space.y * f32(size) * 0.01
		case Percent_Of_Remaining_Height:
			actual_size[i] = available_space.y * f32(size) * 0.01
		case Fixed:
			actual_size[i] = f32(size)
			new_desired_size[i] = max(desired_size[i], f32(size))
		case At_Least:
			actual_size[i] = max(available_space[i], f32(size))
			new_desired_size[i] = max(desired_size[i], f32(size))
		case At_Most:
			actual_size[i] = min(available_space[i], f32(size))
			new_desired_size[i] = max(desired_size[i], f32(size))
		case Between:
			actual_size[i] = min(available_space[i], size[0], size[1])
			new_desired_size[i] = max(desired_size[i], size[0])
		case nil:
			actual_size[i] = desired_size[i]
			new_desired_size[i] = desired_size[i]
		}
	}
	return
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
