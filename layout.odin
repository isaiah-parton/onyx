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
	if !object.isolated {
		switch layout.axis {
		case .X:
			layout.desired_size.x += object.desired_size.x
			layout.desired_size.y = max(layout.desired_size.y, object.desired_size.y)
		case .Y:
			layout.desired_size.y += object.desired_size.y
			layout.desired_size.x = max(layout.desired_size.x, object.desired_size.x)
		}
	}

	if object.parent != nil && layout_is_deferred(&object.parent.layout) {
		append(&object.parent.children, object)
		return true
	}
	return false
}

move_object :: proc(object: ^Object, delta: [2]f32) {
	object.box.lo += delta
	object.box.hi += delta
	for child in object.children {
		move_object(child, delta)
	}
}

apply_object_placement :: proc(object: ^Object) {
	assert(object != nil)
	if object.has_known_box || object.parent == nil do return

	size := linalg.max(object.size, object.desired_size)
	if object.parent.layout.axis == .X {
		parent.layout.content_box.lo.x += object.margin.x
	} else {
		parent.layout.content_box.lo.y += object.margin.y
	}

	box: Box
	box, parent.layout.content_box = split_box(
		parent.layout.content_box,
		axis_cut_side(parent.layout.axis),
		size[int(parent.layout.axis)],
	)

	if parent.layout.justify == .Equal_Space {
		parent.layout.content_box.lo[int(layout.axis)] +=
			parent.layout.space_left[int(layout.axis)] / f32(len(parent.children) - 1)
	}

	if layout.axis == .X {
		layout.content_box.lo.x += object.margin.z
		box.lo.y += object.margin.y
		box.hi.y -= object.margin.w
		if size.y < box_height(box) {
			switch layout.align {
			case .Near:
				box.hi.y = box.lo.y + size.y
			case .Far:
				box.lo.y = box.hi.y - size.y
			case .Center:
				box.lo.y = box_center_y(box) - size.y / 2
				box.hi.y = box.lo.y + size.y
			case .Equal_Space:
			}
		}
	} else {
		layout.content_box.lo.y += object.margin.w
		box.lo.x += object.margin.x
		box.hi.x -= object.margin.z
		if size.x < box_width(box) {
			switch layout.align {
			case .Near:
				box.hi.x = box.lo.x + size.x
			case .Far:
				box.lo.x = box.hi.x - size.x
			case .Center:
				box.lo.x = box_center_x(box) - size.x / 2
				box.hi.x = box.lo.x + size.x
			case .Equal_Space:
			}
		}
	}

	object.box = snapped_box(box)

	if layout.justify == .Center {
		move_object(object, layout.space_left * 0.5)
	} else if layout.justify == .Far {
		move_object(object, layout.space_left)
	}
}

inverse_axis :: proc(axis: Axis) -> Axis {
	return Axis(1 - int(axis))
}

object_defers_children :: proc(object: ^Object) -> bool {
	return (object.content_justify != .Near) || (!object.has_known_box)
}

object_is_deferred :: proc(object: ^Object) -> bool {
	return (!object.has_known_box)
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

begin_layout :: proc(
	size: Layout_Size = nil,
	placement: Future_Object_Placement = nil,
	axis: Axis = .X,
	justify: Align = .Near,
	align: Align = .Near,
	padding: [4]f32 = {},
	clip_contents: bool = false,
) -> bool {
	object := transient_object()
	object.in_state_mask = OBJECT_STATE_ALL
	object.variant = Layout {
		object        = object,
		axis          = axis,
		justify       = justify,
		align         = align,
		clip_contents = clip_contents,
	}
	layout := &object.variant.(Layout)

	switch v in placement {
	case Box:
		layout.isolated = true
		layout.has_known_box = true
		layout.box = v
		layout.size = box_size(v)
	case Future_Box_Placement:
		layout.isolated = true
		layout.future_placement = v
	case nil:
		parent_layout := current_layout()
		layout.size, layout.desired_size, layout.has_known_box = determine_layout_size(
			size,
			parent_layout,
			layout.axis,
		)
		if layout.has_known_box {
			if parent_layout, ok := parent_layout.?; ok {
				layout.box, parent_layout.content_box = split_box(
					parent_layout.content_box,
					axis_cut_side(parent_layout.axis),
					layout.size[int(parent_layout.axis)],
				)
			}
		}
	}

	layout.spacing_size += padding.xy + padding.zw

	layout.content_box = layout.box
	layout.padding = padding
	if !layout_is_deferred(layout) {
		layout.content_box.lo += layout.padding.xy
		layout.content_box.hi -= layout.padding.zw
	}

	begin_object(layout) or_return
	push_layout(layout) or_return
	return true
}

end_layout :: proc() {
	layout := current_layout().?

	pop_layout()
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
	if parent_layout, ok := parent_layout.?; ok {
		available_space = box_size(parent_layout.content_box)
		j = int(parent_layout.axis)
		i = 1 - j
		if layout_is_deferred(parent_layout) {
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

set_size_method :: proc(method: Object_Size_Method) {
	current_layout().?.object_size_method = method
}

set_width :: proc(width: f32) {
	current_layout().?.object_size.x = width
}

set_width_auto :: proc() {
	current_layout().?.object_size.x = 0
}

set_width_fill :: proc() {
	layout := current_layout().?
	layout.object_size.x = box_width(layout.content_box)
}

set_width_percent :: proc(width: f32) {
	layout := current_layout().?
	layout.object_size.x = box_width(layout.content_box) * (width / 100)
}

set_height :: proc(height: f32) {
	current_layout().?.object_size.y = height
}

set_height_auto :: proc() {
	current_layout().?.object_size.y = 0
}

set_height_fill :: proc() {
	layout := current_layout().?
	layout.object_size.y = box_height(layout.content_box)
}

set_height_percent :: proc(height: f32) {
	layout := current_layout().?
	layout.object_size.y = box_height(layout.content_box) * (height / 100)
}

set_margin_sides :: proc(
	left: Maybe(f32) = nil,
	right: Maybe(f32) = nil,
	top: Maybe(f32) = nil,
	bottom: Maybe(f32) = nil,
) {
	layout := current_layout().?
	if left, ok := left.?; ok do layout.object_margin.x = left
	if top, ok := top.?; ok do layout.object_margin.y = top
	if right, ok := right.?; ok do layout.object_margin.z = right
	if bottom, ok := bottom.?; ok do layout.object_margin.w = bottom
}

set_margin_all :: proc(amount: f32) {
	current_layout().?.object_margin = amount
}

set_margin :: proc {
	set_margin_sides,
	set_margin_all,
}

set_width_to_height :: proc() {
	layout := current_layout().?
	layout.object_size.x = layout.object_size.y
}

set_height_to_width :: proc() {
	layout := current_layout().?
	layout.object_size.y = layout.object_size.x
}
