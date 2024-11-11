package onyx

import "../vgo"
import "base:runtime"
import "core:fmt"
import "core:math"
import "core:math/linalg"

Axis :: enum {
	X,
	Y,
}

Object_Size_Method :: enum {
	Maximum,
	Minimum,
	Fixed,
}

Layout_Size_Mode :: enum {
	Fixed,
	Available,
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
	using object:   ^Object,
	axis:           Axis,
	content_box:    Box,
	justify:        Align,
	align:          Align,
	padding:        [2]f32,
	isolated:       bool,
	mode:           Object_Size_Method,
	content_size:   [2]f32,
	spacing_size:   [2]f32,
	object_size:    [2]f32,
	object_padding: [2]f32,
	object_margin:  [4]f32,
	objects:        ^[dynamic]^Object,
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
		cut_box_left(&layout.content_box, object.margin.x)
	} else {
		cut_box_top(&layout.content_box, object.margin.y)
	}

	box: Box
	box, layout.content_box = split_box(
		layout.content_box,
		axis_cut_side(layout.axis),
		size[int(layout.axis)],
	)

	if layout.axis == .X {
		cut_box_left(&layout.content_box, object.margin.z)
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
		cut_box_top(&layout.content_box, object.margin.w)
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
	box.lo += layout.object_padding
	box.hi -= layout.object_padding
	object.box = snapped_box(box)
}

display_layout :: proc(layout: ^Layout) {
	if layout.objects == nil do return
	layout.content_box = shrink_box(layout.box, layout.padding)

	delta := axis_normal(layout.axis) * (box_size(layout.box) - layout.desired_size)
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
	return layout.justify != .Near || !layout.fixed
}

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

begin_layout :: proc(size: union {
		Fixed,
		At_Least,
		At_Most,
		Between,
	} = nil, axis: Axis = .X, box: Maybe(Box) = nil, justify: Align = .Near, align: Align = .Near) -> bool {
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
		if parent_layout, ok := parent_layout.?; ok {
			available_space = box_size(parent_layout.content_box)
			j = int(parent_layout.axis)
		}
		object.fixed = true
		switch size in size {
		case Fixed:
			object.size[j] = f32(size)
			object.desired_size[j] = f32(size)
		case At_Least:
			object.size[j] = max(available_space[j], f32(size))
			object.desired_size[j] = f32(size)
		case At_Most:
			object.size[j] = min(available_space[j], f32(size))
			object.desired_size[j] = f32(size)
		case Between:
			object.size[j] = min(available_space[j], size[0], size[1])
			object.desired_size[j] = size[0]
		case nil:
			object.fixed = false
		}
		object.size[1 - j] = available_space[1 - j]
		if layout.fixed {
			if parent_layout, ok := parent_layout.?; ok {
				object.box, parent_layout.content_box = split_box(
					parent_layout.content_box,
					axis_cut_side(parent_layout.axis),
					object.size[int(parent_layout.axis)],
				)
			}
		}
	}
	layout.content_box = layout.box
	begin_object(object) or_return
	push_layout(&object.variant.(Layout)) or_return
	return true
}

end_layout :: proc() {
	layout := current_layout().?
	layout.desired_size = linalg.max(layout.desired_size, layout.content_size + layout.spacing_size)
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

// next_object_size :: proc(layout: ^Layout, desired_size: [2]f32, fixed: bool = false) -> [2]f32 {
// 	non_fixed_size :: proc(layout: ^Layout, desired_size: [2]f32) -> [2]f32 {
// 		if layout.mode == .Maximum {
// 			return linalg.max(layout.object_size, desired_size)
// 		} else if layout.mode == .Minimum {
// 			return linalg.min(layout.object_size, desired_size)
// 		}
// 		return layout.object_size
// 	}
// 	return linalg.min(
// 		desired_size if fixed else non_fixed_size(layout, desired_size),
// 		layout.content_box.hi - layout.content_box.lo,
// 	)
// }

set_mode :: proc(mode: Object_Size_Method) {
	current_layout().?.mode = mode
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

set_padding_x :: proc(amount: f32) {
	current_layout().?.object_padding.x = amount
}

set_padding_y :: proc(amount: f32) {
	current_layout().?.object_padding.y = amount
}

set_padding :: proc(amount: f32) {
	current_layout().?.object_padding = amount
}

add_padding :: proc(amount: f32) {
	layout := current_layout().?
	layout.spacing_size += amount * 2
	if layout_is_deferred(layout) {
		layout.padding = amount
	} else {
		layout.content_box.lo += amount
		layout.content_box.hi -= amount
	}
}

set_width_to_height :: proc() {
	layout := current_layout().?
	layout.object_size.x = layout.object_size.y
}

set_height_to_width :: proc() {
	layout := current_layout().?
	layout.object_size.y = layout.object_size.x
}

layout_is_vertical :: proc(layout: ^Layout) -> bool {
	return layout.axis == .Y
}
