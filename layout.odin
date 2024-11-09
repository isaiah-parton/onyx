package onyx

import "../vgo"
import "core:math"
import "core:math/linalg"

Axis :: enum {
	X,
	Y,
}

Layout_Mode :: enum {
	Maximum,
	Minimum,
	Absolute,
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
	content_size:   [2]f32,
	spacing_size:   [2]f32,
	isolated:       bool,
	mode:           Layout_Mode,
	object_size:    [2]f32,
	object_padding: [2]f32,
	array:          Maybe(^[dynamic]^Object),
}

axis_normal :: proc(axis: Axis) -> [2]f32 {
	return {f32(1 - i32(axis)), f32(i32(axis))}
}

display_or_add_object :: proc(object: ^Object) {
	if layout, ok := current_layout().?; ok {
		if layout_needs_array(layout) {
			append(layout.array.?, object)
			when ODIN_DEBUG {
				global_state.debug.deferred_objects += 1
			}
			return
		}
	}
	display_object(object)
}

move_object :: proc(object: ^Object, delta: [2]f32) {
	object.box.lo += delta
	object.box.hi += delta
	if layout, ok := object.variant.(Layout); ok {
		for child in layout.array.? {
			move_object(child, delta)
		}
	}
}

display_layout :: proc(layout: ^Layout) {
	if array, ok := layout.array.?; ok {
		for object in array {
			size := layout.content_box.hi[int(layout.axis)] - layout.content_box.lo[int(layout.axis)]
			if layout.justify == .Center {
				move_object(object, size * axis_normal(layout.axis) * 0.5)
			} else if layout.justify == .Far {
				move_object(object, size * axis_normal(layout.axis))
			}
			display_object(object)
		}
	}
}

push_layout :: proc(layout: Layout) -> bool {
	global_state.current_layout =
	&global_state.layout_stack.items[global_state.layout_stack.height]
	return push_stack(&global_state.layout_stack, layout)
}

pop_layout :: proc() {
	pop_stack(&global_state.layout_stack)
	index := global_state.layout_stack.height - 1
	if index >= 0 {
		global_state.current_layout = &global_state.layout_stack.items[index]
		return
	}
	global_state.current_layout = nil
}

begin_layout_with_options :: proc(side: Side, size: f32, axis: Axis) -> bool {
	layout := current_layout().? or_return
	return begin_layout_with_box(
		cut_box(&layout.content_box, side, size),
		axis = axis,
	)
}

next_layout_axis :: proc() -> (axis: Axis, ok: bool) {
	layout := current_layout().? or_return
	return Axis(1 - int(layout.axis)), true
}

next_layout_array :: proc() -> ^[dynamic]^Object {
	non_zero_resize(&global_state.layout_array_array, max(global_state.layout_array_count + 1, len(global_state.layout_array_array)))
	array := &global_state.layout_array_array[global_state.layout_array_count]
	assert(array != nil)
	global_state.layout_array_count += 1
	clear(array)
	return array
}

layout_needs_array :: proc(layout: ^Layout) -> bool {
	return layout.justify == .Center
}

begin_layout_with_box :: proc(
	box: Box,
	axis: Maybe(Axis) = nil,
	justify: Align = .Near,
	isolated: bool = false,
) -> bool {
	object := transient_object()
	object.box = box
	layout := Layout {
		object      = object,
		isolated    = isolated,
		content_box = box,
		justify     = justify,
		axis        = axis.? or_else (next_layout_axis() or_else Axis.X),
	}
	if layout_needs_array(&layout) {
		layout.array = next_layout_array()
	}
	object.variant = layout
	push_layout(layout) or_return
	begin_object(object) or_return
	return true
}

begin_layout_full :: proc() -> bool {
	return begin_layout_with_box(layout_box())
}

begin_layout :: proc {
	begin_layout_full,
	begin_layout_with_box,
	begin_layout_with_options,
}

end_layout :: proc() {
	layout := current_layout().?

	when ODIN_DEBUG {
		if global_state.debug.enabled {
			vgo.stroke_box(layout.box, 1, paint = vgo.RED)
		}
	}

	pop_layout()
	end_object()

	display_or_add_object(layout)

	if layout.isolated do return

	if parent_layout, ok := current_layout().?; ok {
		size := linalg.max(
			layout.content_size + layout.spacing_size,
			box_size(layout.box) *
			[2]f32{1 - f32(i32(parent_layout.axis)), f32(i32(parent_layout.axis))},
		)
		if parent_layout.axis == .X {
			parent_layout.content_size.y = max(parent_layout.content_size.y, size.y)
			parent_layout.content_size.x += size.x
		} else {
			parent_layout.content_size.x = max(parent_layout.content_size.x, size.x)
			parent_layout.content_size.y += size.y
		}
	}
}

begin_row :: proc(height: f32, justify: H_Align) -> bool {
	layout := current_layout().?
	return begin_layout_with_box(
		cut_layout(layout, size = [2]f32{box_width(layout.content_box), height}),
		axis = .X,
		justify = Align(justify),
	)
}

end_row :: proc() {
	end_layout()
}

begin_column :: proc(width: f32, justify: V_Align) -> bool {
	layout := current_layout().?
	return begin_layout_with_box(
		cut_layout(layout, size = [2]f32{width, box_height(layout.content_box)}),
		axis = .Y,
		justify = Align(justify),
	)
}

end_column :: proc() {
	end_layout()
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

layout_cut_side :: proc(layout: ^Layout) -> Side {
	side: Side
	if layout.axis == .X {
		side = .Right if layout.justify == .Far else .Left
	} else {
		side = .Bottom if layout.justify == .Far else .Top
	}
	return side
}

cut_layout :: proc(layout: ^Layout, side: Maybe(Side) = nil, size: Maybe([2]f32) = nil) -> Box {
	size := size.? or_else layout.object_size
	box := cut_box(
		&layout.content_box,
		side.? or_else layout_cut_side(layout),
		size[int(layout.axis)],
	)
	return box
}

cut_current_layout :: proc(side: Maybe(Side) = nil, size: Maybe([2]f32) = nil) -> Box {
	return cut_layout(current_layout().?, side, size)
}

next_object_size :: proc(desired_size: [2]f32, fixed: bool = false) -> [2]f32 {
	non_fixed_size :: proc(layout: ^Layout, desired_size: [2]f32) -> [2]f32 {
		if layout.mode == .Maximum {
			return linalg.max(layout.object_size, desired_size)
		} else if layout.mode == .Minimum {
			return linalg.min(layout.object_size, desired_size)
		}
		return layout.object_size
	}
	layout := current_layout().?
	return linalg.min(
		desired_size if fixed else non_fixed_size(layout, desired_size),
		layout.content_box.hi - layout.content_box.lo,
	)
}

next_object_box :: proc(size: [2]f32) -> Box {
	layout := current_layout().?
	box := cut_layout(layout, nil, size)
	if layout.axis == .Y {
		if size.x < box_width(box) {
			switch layout.align {
			case .Near:
				box.hi.x = box.lo.x + size.x
			case .Far:
				box.lo.x = box.hi.x - size.x
			case .Center:
				break
			}
		}
	} else {
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
	}
	box.lo += layout.object_padding
	box.hi -= layout.object_padding
	return snapped_box(box)
}

set_mode :: proc(mode: Layout_Mode) {
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
set_width_to_height :: proc() {
	layout := current_layout().?
	layout.object_size.x = layout.object_size.y
}
set_height_to_width :: proc() {
	layout := current_layout().?
	layout.object_size.y = layout.object_size.x
}

add_padding :: proc(amount: [2]f32) {
	layout := current_layout().?
	layout.content_box.lo += amount
	layout.content_box.hi -= amount
	layout.spacing_size += amount * 2
}
add_padding_x :: proc(amount: f32) {
	layout := current_layout().?
	layout.content_box.lo.x += amount
	layout.content_box.hi.x -= amount
}
add_padding_y :: proc(amount: f32) {
	layout := current_layout().?
	layout.content_box.lo.y += amount
	layout.content_box.hi.y -= amount
}
add_space :: proc(amount: f32) {
	layout := current_layout().?
	cut_box(&layout.content_box, layout_cut_side(layout), amount)
	layout.spacing_size[int(layout.axis)] += amount
}

layout_is_vertical :: proc(layout: ^Layout) -> bool {
	return layout.axis == .Y
}

add_layout_content_size :: proc(layout: ^Layout, size: [2]f32) {
	if layout_is_vertical(layout) {
		layout.content_size.x = max(layout.content_size.x, size.x)
		layout.content_size.y += size.y
	} else {
		layout.content_size.y = max(layout.content_size.y, size.y)
		layout.content_size.x += size.x
	}
}
