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

Layout :: struct {
	using object:  ^Object,
	isolated:      bool,
	axis:          Axis,
	content_box:   Box,
	justify:       Align,
	align:         Align,
	method:        Object_Size_Method,
	padding:       [4]f32,
	content_size:  [2]f32,
	spacing_size:  [2]f32,
	object_size:   [2]f32,
	object_margin: [4]f32,
	objects:       ^[dynamic]^Object,
}

Object_Placement :: struct {
	size:    [2]f32,
	padding: [2]f32,
	margin:  [4]f32,
	mode:    Object_Size_Method,
}

store_object_in_layout :: proc(object: ^Object, layout: ^Layout) {
	append(layout.objects, object)
}

axis_normal :: proc(axis: Axis) -> [2]f32 {
	return {f32(1 - i32(axis)), f32(i32(axis))}
}

display_or_add_object :: proc(object: ^Object, layout: ^Layout) {
	switch layout.axis {
	case .X:
		layout.desired_size.x += object.desired_size.x
		layout.desired_size.y = max(layout.desired_size.y, object.desired_size.y)
	case .Y:
		layout.desired_size.y += object.desired_size.y
		layout.desired_size.x = max(layout.desired_size.x, object.desired_size.x)
	}

	if layout_is_deferred(layout) {
		store_object_in_layout(object, layout)
		return
	}

	if !object.fixed {
		apply_object_layout(object, layout)
	}
	display_object(object)
}

move_object :: proc(object: ^Object, delta: [2]f32) {
	object.box.lo += delta
	object.box.hi += delta
	if layout, ok := object.variant.(Layout); ok {
		for child in layout.objects {
			move_object(child, delta)
		}
	}
}

apply_object_layout :: proc(object: ^Object, layout: ^Layout) {
	size := linalg.max(object.size, object.desired_size)
	if layout.axis == .X {
		layout.content_box.lo.x += object.margin.x
		size.y -= object.margin.y + object.margin.w
	} else {
		layout.content_box.lo.y += object.margin.y
		size.x -= object.margin.x + object.margin.z
	}

	box: Box
	box, layout.content_box = split_box(
		layout.content_box,
		axis_cut_side(layout.axis),
		size[int(layout.axis)],
	)

	if layout.axis == .X {
		layout.content_box.lo.x += object.margin.z
		if size.y < box_height(box) {
			switch layout.align {
			case .Near:
				box.hi.y = box.lo.y + size.y
			case .Far:
				box.lo.y = box.hi.y - size.y
			case .Center:
				box.lo.y = box_center_y(box) - size.y / 2
				box.hi.y = box.lo.y + size.y
			}
		}
	} else {
		layout.content_box.lo.y += object.margin.w
		if size.x < box_width(box) {
			switch layout.align {
			case .Near:
				box.hi.x = box.lo.x + size.x
			case .Far:
				box.lo.x = box.hi.x - size.x
			case .Center:
				box.lo.x = box_center_x(box) - size.x / 2
				box.hi.x = box.lo.x + size.x
			}
		}
	}

	object.box = snapped_box(box)
}

display_layout :: proc(layout: ^Layout) {
	layout.content_box = layout.box
	layout.content_box.lo += layout.padding.xy
	layout.content_box.hi -= layout.padding.zw

	delta := axis_normal(layout.axis) * (box_size(layout.box) - layout.desired_size)

	if layout.objects == nil do return

	for object in layout.objects {
		apply_object_layout(object, layout)
		if layout.justify == .Center {
			move_object(object, linalg.floor(delta * 0.5))
		} else if layout.justify == .Far {
			move_object(object, delta)
		}
		display_object(object)
	}
}

push_layout :: proc(layout: ^Layout) -> bool {
	push_stack(&global_state.layout_stack, layout) or_return
	global_state.current_layout =
		global_state.layout_stack.items[global_state.layout_stack.height - 1]
	return true
}

pop_layout :: proc() {
	pop_stack(&global_state.layout_stack)
	index := global_state.layout_stack.height - 1
	if index >= 0 {
		global_state.current_layout = global_state.layout_stack.items[index]
		return
	}
	global_state.current_layout = nil
}

inverse_axis :: proc(axis: Axis) -> Axis {
	return Axis(1 - int(axis))
}

next_layout_array :: proc() -> ^[dynamic]^Object {
	array := &global_state.layout_array_array[global_state.layout_array_count]
	global_state.layout_array_count += 1
	assert(array != nil)
	clear(array)
	return array
}

layout_is_deferred :: proc(layout: ^Layout) -> bool {
	return (layout.justify != .Near) || !layout.fixed
}

begin_layout :: proc(
	size: union {
		Fixed,
		At_Least,
		At_Most,
		Between,
	} = nil,
	axis: Axis = .X,
	box: Maybe(Box) = nil,
	justify: Align = .Near,
	align: Align = .Near,
	padding: [4]f32 = {},
) -> bool {
	object := transient_object()
	object.variant = Layout {
		object  = object,
		axis    = axis,
		justify = justify,
		align   = align,
		objects = next_layout_array(),
	}
	layout := &object.variant.(Layout)
	if box, ok := box.?; ok {
		layout.isolated = true
		layout.fixed = true
		layout.box = box
	} else {
		available_space: [2]f32
		parent_layout := current_layout()

		i := int(axis)
		j := 1 - int(axis)

		layout.fixed = true
		if parent_layout, ok := parent_layout.?; ok {
			// FIXME: `content_box` does not reflect the amount of available space at this point
			available_space = box_size(parent_layout.content_box) - (parent_layout.padding.xy + parent_layout.padding.zw)
			j = int(parent_layout.axis)
			if layout_is_deferred(parent_layout) {
				layout.fixed = false
			}
		}
		switch size in size {
		case Fixed:
			layout.size[j] = f32(size)
			layout.desired_size[j] = f32(size)
		case At_Least:
			layout.size[j] = max(available_space[j], f32(size))
			layout.desired_size[j] = f32(size)
		case At_Most:
			layout.size[j] = min(available_space[j], f32(size))
		case Between:
			layout.size[j] = min(available_space[j], size[0], size[1])
			layout.desired_size[j] = size[0]
		case nil:
			layout.fixed = false
		}

		layout.size[i] = available_space[i]

		if layout.fixed {
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
	if layout_is_deferred(layout) {
		layout.padding = padding
	} else {
		layout.content_box.lo += padding.xy
		layout.content_box.hi -= padding.zw
	}

	begin_object(layout) or_return
	push_layout(layout) or_return
	return true
}

end_layout :: proc() {
	layout := current_layout().?
	layout.desired_size = linalg.max(
		layout.desired_size,
		layout.content_size + layout.spacing_size,
	)
	pop_layout()
	end_object()
}

current_layout :: proc() -> Maybe(^Layout) {
	if global_state.current_layout != nil {
		return global_state.current_layout
	}
	return nil
}

layout_box :: proc() -> Box {
	return current_layout().?.content_box
}

axis_cut_side :: proc(axis: Axis) -> Side {
	if axis == .X {
		return .Left
	}
	return .Top
}

set_size_method :: proc(method: Object_Size_Method) {
	current_layout().?.method = method
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

set_margin :: proc(
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

set_width_to_height :: proc() {
	layout := current_layout().?
	layout.object_size.x = layout.object_size.y
}

set_height_to_width :: proc() {
	layout := current_layout().?
	layout.object_size.y = layout.object_size.x
}