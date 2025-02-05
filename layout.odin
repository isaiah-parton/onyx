package onyx

import "../vgo"
import "base:runtime"
import "core:fmt"
import "core:math"
import "core:math/linalg"

Options :: struct {
	padding:   [4]f32,
	side:      Side,
	size:      [2]f32,
	align:     Align,
	radius:    [4]f32,
	size_mode: Size_Mode,
	hover_to_focus: bool,
	object_height: int,
}

Size_Mode :: enum {
	Max,
	Min,
	Fixed,
}

default_options :: proc() -> Options {
	return Options{radius = style().rounding, size_mode = .Max, side = .Top}
}

current_options :: proc() -> ^Options {
	return &global_state.options_stack.items[max(global_state.options_stack.height - 1, 0)]
}

push_current_options :: proc() {
	push_stack(&global_state.options_stack, current_options()^)
}

push_options :: proc(options: Options = {}) {
	push_stack(&global_state.options_stack, options)
}

pop_options :: proc() {
	pop_stack(&global_state.options_stack)
}

Layout :: struct {
	box:          Box,
	bounds:       Box,
	does_grow:    bool,
	spacing_size: [2]f32,
	content_size: [2]f32,
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

next_box_is_fully_clipped :: proc() -> bool {
	box := next_box({})
	set_next_box(box)
	return get_clip(current_clip(), box) == .Full
}

next_user_defined_box :: proc() -> (box: Box, ok: bool) {
	box, ok = global_state.next_box.?
	if ok {
		global_state.next_box = nil
	}
	return
}

next_box_from_current_layout :: proc(size: [2]f32, fixed: bool) -> Box {
	return next_box_from_layout(current_layout().?, current_options(), size, fixed)
}

solve_layout_content_size :: proc(total: [2]f32, side: Side, size: [2]f32) -> [2]f32 {
	if int(side) > 1 {
		return {max(total.x, size.x), total.y + size.y}
	}
	return {total.x + size.x, max(total.y, size.y)}
}

grow_side_of_box :: proc(box: Box, side: Side, size: [2]f32) -> Box {
	box := box
	switch side {
	case .Top:
		box.hi.y = max(box.hi.y, box.lo.y + size.y)
	case .Bottom:
		box.lo.y = min(box.lo.y, box.hi.y - size.y)
	case .Left:
		box.hi.x = max(box.hi.x, box.lo.x + size.x)
	case .Right:
		box.lo.x = min(box.lo.x, box.hi.x - size.x)
	}
	return box
}

next_box_from_layout :: proc(
	layout: ^Layout,
	options: ^Options,
	size: [2]f32,
	fixed: bool,
) -> Box {
	i := int(options.side) / 2
	j := 1 - i

	size := size
	if !fixed {
		switch options.size_mode {
		case .Max:
			size = linalg.max(size, options.size)
		case .Min:
			size = linalg.min(size, options.size)
		case .Fixed:
			size = options.size
		}
	}

	if !layout.does_grow {
		size = linalg.min(size, box_size(layout.box))
	}

	layout.content_size = solve_layout_content_size(layout.content_size, options.side, size)

	if layout.does_grow {
		layout.box = grow_side_of_box(layout.box, options.side, size)
	}

	box := cut_box(&layout.box, options.side, size[i])

	box.lo += options.padding.xy
	box.hi -= options.padding.zw

	size -= (options.padding.xy + options.padding.zw)

	switch options.align {
	case .Near:
		box.hi[j] = box.lo[j] + size[j]
	case .Center:
		baseline := (box.hi[j] + box.lo[j]) / 2
		box.lo[j] = baseline - size[j] / 2
		box.hi[j] = baseline + size[j] / 2
	case .Far:
		box.lo[j] = box.hi[j] - size[j]
	}

	return box//snapped_box(box)
}

axis_normal :: proc(axis: Axis) -> [2]f32 {
	return {f32(1 - i32(axis)), f32(i32(axis))}
}

inverse_axis :: proc(axis: Axis) -> Axis {
	return Axis(1 - int(axis))
}

current_axis :: proc() -> Axis {
	return axis_of_side(current_options().side)
}

current_box :: proc() -> Box {
	if layout, ok := current_layout().?; ok {
		return layout.box
	}
	if object, ok := current_object().?; ok {
		return object.box
	}
	return view_box()
}

begin_layout :: proc(side: Side, size: [2]f32 = {}, does_grow: bool = false) -> bool {
	box := next_box(size)
	layout := Layout {
		does_grow = does_grow,
		box       = box,
		bounds    = box,
	}
	options := current_options()^
	options.side = side
	push_options(options)
	return push_layout(layout)
}

end_layout :: proc() {
	pop_layout()
	pop_options()
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
	layout.spacing_size += (amount.xy + amount.zw)
}

space :: proc(amount: f32) {
	layout := current_layout().?
	cut_box(&layout.box, current_options().side, amount)
}

set_size_mode :: proc(mode: Size_Mode) {
	current_options().size_mode = mode
}

set_size :: proc(size: [2]f32) {
	current_options().size = size
}

set_next_box :: proc(box: Box) {
	global_state.next_box = box
}

set_width :: proc(width: f32) {
	current_options().size.x = width
}

set_height :: proc(height: f32) {
	current_options().size.y = height
}

set_padding :: proc(padding: [4]f32) {
	current_options().padding = padding
}

remaining_space :: proc() -> [2]f32 {
	layout := current_layout().?
	return layout.box.hi - layout.box.lo
}

set_side :: proc(side: Side) {
	current_options().side = side
}

set_align :: proc(align: Align) {
	current_options().align = align
}

wiggle_next_object :: proc(time, amount: f32) {
	box := next_box({})
	box = move_box(box, {math.sin(f32(seconds()) * 30) * math.sin(time * math.PI) * amount, 0})
	set_next_box(box)
	draw_frames(int(time > 0 && time < 1) * 2)
}
