package onyx

import kn "../../katana/katana"
import "base:runtime"
import "core:fmt"
import "core:math"
import "core:math/linalg"

golden_ratio :: 1.618033988749
phi :: golden_ratio
φ :: golden_ratio

Layout :: struct {
	box:          Box,
	bounds:       Box,
	side:         Side,
	does_grow:    bool,
	show_wireframe: bool,
	spacing_size: [2]f32,
	content_size: [2]f32,
	cut_side:     Side,
}

Layout_Direction :: enum {
	Normal,
	Reversed,
}

Dynamic :: struct {
}
Show_Wireframe :: distinct bool
Split_Into :: distinct f32
Split_By :: distinct f32
Define_Content_Sizes :: []f32
Cut_Contents_From_Side :: distinct Side
Cut_From_Side :: distinct Side

on_left :: Cut_From_Side(.Left)
on_right :: Cut_From_Side(.Right)
on_top :: Cut_From_Side(.Top)
on_bottom :: Cut_From_Side(.Bottom)

left_to_right :: Cut_Contents_From_Side(.Left)
right_to_left :: Cut_Contents_From_Side(.Right)
top_to_bottom :: Cut_Contents_From_Side(.Top)
bottom_to_top :: Cut_Contents_From_Side(.Bottom)

as_row :: left_to_right
as_reversed_row :: right_to_left
as_column :: top_to_bottom
as_reversed_column :: bottom_to_top
split_halves :: Split_Into(2)
split_thirds :: Split_Into(3)
split_fourths :: Split_Into(4)
split_fifths :: Split_Into(5)
split_sixths :: Split_Into(6)
split_sevenths :: Split_Into(7)
split_golden :: Split_Into(golden_ratio)
is_dynamic :: Dynamic{}
with_wireframe :: Show_Wireframe(true)

Layout_Property :: union {
	Cut_From_Side,
	Cut_Contents_From_Side,
	Define_Content_Sizes,
	Dynamic,
	Split_Into,
	Split_By,
	Show_Wireframe,
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

get_current_layout :: proc() -> ^Layout {
	assert(global_state.layout_stack.height > 0)
	return &global_state.layout_stack.items[global_state.layout_stack.height - 1]
}

push_layout :: proc(layout: Layout) -> bool {
	return push_stack(&global_state.layout_stack, layout)
}

pop_layout :: proc() {
	pop_stack(&global_state.layout_stack)
}

next_user_defined_box :: proc() -> (box: Box, ok: bool) {
	box, ok = global_state.next_box.?
	if ok {
		global_state.next_box = nil
	}
	return
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

solve_size :: proc(option_size, object_size: f32, method: Size_Method) -> f32 {
	switch method {
	case .Dont_Care:
		return object_size
	case .Fixed:
		return option_size
	case .Max:
		return max(option_size, object_size)
	case .Min:
		return min(option_size, object_size)
	}
	return option_size
}

place_object_in_layout :: proc(object: ^Object, layout: ^Layout) -> Box {
	options := get_current_options()

	axis := int(layout.side) / 2
	axis2 := 1 - axis

	cut_size := solve_size(options.size[axis], object.size[axis], options.methods[axis])
	// fit_size := solve_size(options.size[axis2], object.size[axis2], options.methods[axis2])

	if !layout.does_grow {
		cut_size = min(cut_size, layout.box.hi[axis] - layout.box.lo[axis])
	}

	if layout.does_grow {
		layout.box = grow_side_of_box(layout.box, layout.side, cut_size)
	}

	box := cut_box(&layout.box, layout.side, cut_size)

	box.lo += options.padding.xy
	box.hi -= options.padding.zw

	if int(layout.side) > 1 {
		layout.content_size.x = max(object.size.x, layout.content_size.x)
		layout.content_size.y += object.size.y
	} else {
		layout.content_size.y = max(object.size.y, layout.content_size.y)
		layout.content_size.x += object.size.x
	}

	if object.size_is_fixed {
		box = align_box_inside(box, object.size, options.align)
	}

	return snapped_box(box)
}

cut_layout :: proc(side: Side, amount: f32) -> Box {
	layout := get_current_layout()
	return cut_box(&layout.box, side, amount)
}

axis_normal :: proc(axis: int) -> [2]f32 {
	return {f32(1 - axis), f32(axis)}
}

cut_side_normal :: proc(side: Side) -> [2]f32 {
	axis := int(side) / 2
	return {f32(1 - axis), f32(axis)}
}

inverse_axis :: proc(axis: Axis) -> Axis {
	return Axis(1 - int(axis))
}

get_current_axis :: proc() -> int {
	return int(get_current_layout().side) / 2
}


begin_layout :: proc(props: ..Layout_Property) -> bool {
	current_layout := get_current_layout()
	current_axis := int(current_layout.side) / 2
	cut_from_side := current_layout.side
	cut_contents_from_side := Side.Left
	layout := Layout{}
	options := get_current_options()^
	size_option: Size_Option
	for prop in props {
		#partial switch v in prop {
		case Cut_From_Side:
			cut_from_side = Side(v)
		case Cut_Contents_From_Side:
			cut_contents_from_side = Side(v)
		case Dynamic:
			layout.does_grow = true
		case Split_By:
			size_option = Factor_Of_Remaining_Cut_Space(v)
		case Split_Into:
			size_option = Factor_Of_Remaining_Cut_Space(1 / v)
		case Show_Wireframe:
			layout.show_wireframe = bool(v)
		}
	}
	box := cut_box(
		&current_layout.box,
		cut_from_side,
		solve_size(options.size[current_axis], 0, options.methods[current_axis]),
	)
	layout.side = cut_contents_from_side
	layout.box = box
	layout.bounds = box
	push_options(options)
	ok := push_layout(layout)
	set_cut_size(size_option)
	if layout.show_wireframe {
		kn.stroke_box(layout.box, 1, paint = get_current_style().color.foreground_stroke)
	}
	return ok
}

end_layout :: proc() {
	layout := get_current_layout()
	pop_layout()
	next_layout := get_current_layout()
	next_layout.spacing_size += layout.spacing_size
	if int(layout.cut_side) > 1 {
		next_layout.content_size.x = max(layout.content_size.x, next_layout.content_size.x)
		next_layout.content_size.y += layout.content_size.y
	} else {
		next_layout.content_size.y = max(layout.content_size.y, next_layout.content_size.y)
		next_layout.content_size.x += layout.content_size.x
	}
	pop_options()
}

@(deferred_out = __do_layout)
do_layout :: proc(props: ..Layout_Property) -> bool {
	return begin_layout(..props)
}

@(private)
__do_layout :: proc(ok: bool) {
	if ok {
		end_layout()
	}
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
	layout := get_current_layout()
	layout.box.lo += amount.xy
	layout.box.hi -= amount.zw
	layout.spacing_size += (amount.xy + amount.zw)
}

space :: proc() {
	layout := get_current_layout()
	axis := int(layout.side) / 2
	cut_size := solve_size(get_current_options().size[axis], 0, .Fixed)
	cut_box(&layout.box, layout.side, cut_size)
	layout.spacing_size[axis] += cut_size
}

set_next_box :: proc(box: Box) {
	global_state.next_box = box
}

set_padding :: proc(padding: [4]f32) {
	get_current_options().padding = padding
}

remaining_space :: proc() -> [2]f32 {
	layout := get_current_layout()
	return layout.box.hi - layout.box.lo
}


set_align :: proc(align: [2]f32) {
	get_current_options().align = align
}
