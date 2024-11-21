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
At_Most :: distinct f32
Between :: distinct [2]f32

Axis :: enum {
	X,
	Y,
}

Object_Size_Method :: enum {
	Maximum,
	Minimum,
	Fixed,
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

H_Align :: enum {
	Left,
	Center,
	Right,
}

V_Align :: enum {
	Top,
	Center,
	Bottom,
}

Object_Layout_Options :: struct {
	size:   [2]Layout_Size,
	margin: [4]f32,
	align:  Align,
	method: Object_Size_Method,
}

axis_normal :: proc(axis: Axis) -> [2]f32 {
	return {f32(1 - i32(axis)), f32(i32(axis))}
}

maybe_defer_object :: proc(object: ^Object) -> bool {
	parent := object.parent.? or_return
	object_defers_children(parent) or_return
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
	if object.has_known_box do return false
	parent := object.parent.? or_return

	content_box := parent.content.box

	object.box, content_box = split_box(
		apply_near_object_margin(
			content_box,
			parent.content.axis,
			object.metrics.margin,
		),
		axis_cut_side(parent.content.axis),
		object.metrics.size[int(parent.content.axis)],
	)

	content_box = apply_far_object_margin(
		content_box,
		parent.content.axis,
		object.metrics.margin,
	)

	object.box = snapped_box(
		apply_object_alignment(
			apply_perpendicular_object_margin(
				object.box,
				parent.content.axis,
				object.metrics.margin,
			),
			parent.content.axis,
			parent.content.align,
			object.metrics.size,
		),
	)

	if parent.content.justify == .Equal_Space {
		content_box.lo[int(parent.content.axis)] +=
		parent.content.space_left[int(parent.content.axis)] / f32(len(parent.children) - 1)
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
	return (object.content.justify != .Near) || (!object.has_known_box)
}

object_is_deferred :: proc(object: ^Object) -> bool {
	return !object.has_known_box
}

Future_Box_Placement :: struct {
	origin: [2]f32,
	offset: [2]f32,
}

Layout_Size :: union {
	Fixed,
	At_Least,
	At_Most,
	Between,
	Percent,
}

Object_Placement :: union {
	Box,
	Future_Box_Placement,
	Future_Layout_Placement,
}

begin_row_layout :: proc(
	size: Layout_Size = nil,
	justify: Align = .Near,
	padding: [4]f32 = 0,
) -> bool {
	return begin_layout(
		placement = Future_Layout_Placement{
			size = size,
		},
		axis = .X,
		justify = justify,
		padding = padding,
	)
}

begin_column_layout :: proc(
	size: Layout_Size = nil,
	justify: Align = .Near,
	padding: [4]f32 = 0,
) -> bool {
	return begin_layout(
		placement = Future_Layout_Placement{
			size = size,
		},
		axis = .Y,
		justify = justify,
		padding = padding,
	)
}

begin_layout :: proc(
	placement: Object_Placement = nil,
	axis: Axis = .X,
	justify: Align = .Near,
	padding: [4]f32 = {},
	clip_contents: bool = false,
) -> bool {
	self := transient_object()
	self.state.input_mask = OBJECT_STATE_ALL
	self.content = {
		axis = axis,
		justify = justify,
		padding = padding,
	}

	#partial switch v in placement {
	case Box:
		self.isolated = true
		self.has_known_box = true
		self.box = v
		self.metrics.size = box_size(v)
	case Future_Box_Placement:
		self.isolated = true
		self.future_placement = v
	case Future_Layout_Placement:
		self.metrics.size, self.metrics.desired_size, self.has_known_box = determine_object_size(
			v.size[1 - int(self.content.axis)],
			self.parent,
			self.content.axis,
		)
		if self.has_known_box {
			if parent, ok := current_object().?; ok {
				self.box, parent.content.box = split_box(
					parent.content.box,
					axis_cut_side(parent.content.axis),
					self.metrics.size[int(parent.content.axis)],
				)
			}
		}
	}

	self.content.box = self.box
	self.content.padding = padding
	if !object_defers_children(self) {
		self.content.box.lo += self.content.padding.xy
		self.content.box.hi -= self.content.padding.zw
	}

	begin_object(self) or_return
	push_placement_options()
	return true
}

end_layout :: proc() {
	pop_placement_options()
	end_object()
}

determine_object_size :: proc(
	size: Layout_Size,
	parent: Maybe(^Object),
	axis: Axis,
) -> (
	actual_size: [2]f32,
	desired_size: [2]f32,
	known: bool,
) {
	available_space: [2]f32
	i := int(axis)
	j := 1 - int(axis)
	known = true
	if parent, ok := parent.?; ok {
		available_space = box_size(parent.content.box)
		j = int(parent.content.axis)
		i = 1 - j
		if object_defers_children(parent) {
			known = false
		}
	}
	switch size in size {
	case Percent:
		actual_size[j] = available_space[j] * f32(size) * 0.01
	case Fixed:
		actual_size[j] = f32(size)
		desired_size[j] = f32(size)
	case At_Least:
		actual_size[j] = max(available_space[j], f32(size))
		desired_size[j] = f32(size)
	case At_Most:
		actual_size[j] = min(available_space[j], f32(size))
		desired_size[j] = f32(size)
	case Between:
		actual_size[j] = min(available_space[j], size[0], size[1])
		desired_size[j] = size[0]
	case nil:
		known = false
	}
	actual_size[i] = available_space[i]
	return
}

axis_cut_side :: proc(axis: Axis) -> Side {
	if axis == .X {
		return .Left
	}
	return .Top
}

set_width :: proc(width: f32) {
	current_placement_options().width = Fixed(width)
}

set_width_auto :: proc() {
	current_placement_options().width = nil
}

set_width_fill :: proc() {
	set_width_percent(100)
}

set_width_percent :: proc(percent: f32) {
	current_placement_options().width = Percent(percent)
}

set_height :: proc(height: f32) {
	current_placement_options().height = Fixed(height)
}

set_height_auto :: proc() {
	current_placement_options().height = nil
}

set_height_fill :: proc() {
	set_height_percent(100)
}

set_height_percent :: proc(percent: f32) {
	current_placement_options().height = Percent(percent)
}

set_margin_sides :: proc(
	left: Maybe(f32) = nil,
	right: Maybe(f32) = nil,
	top: Maybe(f32) = nil,
	bottom: Maybe(f32) = nil,
) {
	options := current_placement_options()
	if left, ok := left.?; ok do options.margin.x = left
	if top, ok := top.?; ok do options.margin.y = top
	if right, ok := right.?; ok do options.margin.z = right
	if bottom, ok := bottom.?; ok do options.margin.w = bottom
}

set_margin_all :: proc(amount: f32) {
	current_placement_options().margin = amount
}

set_margin :: proc {
	set_margin_sides,
	set_margin_all,
}

set_width_to_height :: proc() {
	options := current_placement_options()
	options.width = options.height
}

set_height_to_width :: proc() {
	options := current_placement_options()
	options.height = options.width
}
