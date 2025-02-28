package ronin

import "base:runtime"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import kn "local:katana"

Layout :: struct {
	box:            Box,
	bounds:         Box,
	side:           Side,
	is_dynamic:      bool,
	is_root:      bool,
	show_wireframe: bool,
	spacing_size:   [2]f32,
	content_size:   [2]f32,
	desired_size: [2]f32,
	cut_side:       Side,
}

Layout_Property :: union {
	Is_Root,
	Defined_Box,
	Alignment,
	Margin,
	Padding,
	Cut_From_Side,
	Cut_Contents_From_Side,
	Define_Content_Sizes,
	Layout_Is_Dynamic,
	Split_Into,
	Split_By,
}

Box_Cut :: struct {
	side: Side,
	amount: f32,
}

Layout_Placement :: union {
	Box,
	Box_Cut,
}

Layout_Descriptor :: struct {
	options: Options,
	margin: [4]f32,
	padding: [4]f32,
	placement: Layout_Placement,
	size_is_desired: bool,
	is_dynamic: bool,
	cut_contents_from_side: Side,
	content_size_option: Size_Option,
	is_root: bool,
}

make_layout_descriptor :: proc(props: ..Layout_Property) -> Layout_Descriptor {
	desc: Layout_Descriptor = {
		options = get_current_options()^,
	}
	for prop in props {
		#partial switch v in prop {
		case Cut_From_Side:
			side := Side(v)
			axis := int(side) / 2
			desc.placement = Box_Cut{side = side, amount = solve_size(desc.options.size[axis], 0, desc.options.methods[axis])}
			if desc.options.methods[axis] in (bit_set[Size_Method])({.Fixed}) {
				desc.size_is_desired = true
			}
		case Cut_Contents_From_Side:
			desc.cut_contents_from_side = Side(v)
		case Layout_Is_Dynamic:
			desc.is_dynamic = bool(v)
		case Split_By:
			desc.content_size_option = Factor_Of_Remaining_Width_Or_Height(v)
		case Split_Into:
			desc.content_size_option = Factor_Of_Remaining_Width_Or_Height(1 / v)
		case Defined_Box:
			desc.placement = Box(v)
		case Margin:
			desc.margin = ([4]f32)(v)
		case Padding:
			desc.padding = ([4]f32)(v)
		case Alignment:
			desc.options.align = f32(v)
		}
	}
	return desc
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

solve_desired_size :: proc(option_size, object_size: f32, method: Size_Method) -> f32 {
	if method == .Fixed {
		return option_size
	}
	return object_size
}

place_object_in_layout :: proc(object: ^Object, layout: ^Layout) -> Box {
	options := get_current_options()

	axis := int(layout.side) / 2
	axis2 := 1 - axis

	actual_size := [2]f32{
		solve_size(options.size.x, object.size.x, options.methods.x),
		solve_size(options.size.y, object.size.y, options.methods.y)
	}
	desired_size := [2]f32{
		solve_desired_size(options.size.x, object.size.x, options.methods.x),
		solve_desired_size(options.size.y, object.size.y, options.methods.y),
	}

	if layout.is_dynamic {
		layout.box = grow_side_of_box(layout.box, layout.side, actual_size[axis])
	} else {
		actual_size = linalg.min(actual_size, box_size(layout.box))
	}

	box := cut_box(&layout.box, layout.side, actual_size[axis])

	box.lo += options.padding.xy
	box.hi -= options.padding.zw

	if int(layout.side) > 1 {
		layout.content_size.x = max(desired_size.x, layout.content_size.x)
		layout.content_size.y += desired_size.y
	} else {
		layout.content_size.y = max(desired_size.y, layout.content_size.y)
		layout.content_size.x += desired_size.x
	}

	for i in 0..=1 {
		if options.unlocked[i] {
			floating_size := max(object.size[i], options.size[i])
			box.lo[i] = math.lerp(box.lo[i], box.hi[i] - floating_size, options.align[i])
			box.hi[i] = box.lo[i] + floating_size
		}
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

get_current_axis :: proc() -> int {
	return int(get_current_layout().side) / 2
}

begin_layout :: proc(props: ..Layout_Property) -> bool {
	current_layout := get_current_layout()

	layout := Layout{}

	desc := make_layout_descriptor(..props)

	switch v in desc.placement {
	case Box:
		layout.box = v
	case Box_Cut:
		if current_layout.is_dynamic {
			current_layout.box = grow_side_of_box(current_layout.box, v.side, v.amount)
		}
		layout.box = cut_box(&current_layout.box, v.side, v.amount)
		layout.cut_side = v.side
	case nil:
		axis := int(current_layout.side) / 2
		cut := Box_Cut{side = current_layout.side, amount = solve_size(desc.options.size[axis], 0, desc.options.methods[axis])}
		if current_layout.is_dynamic {
			current_layout.box = grow_side_of_box(current_layout.box, cut.side, cut.amount)
		}
		layout.box = cut_box(&current_layout.box, cut.side, cut.amount)
		layout.cut_side = cut.side
	}

	if desc.size_is_desired {
		// layout.desired_size = box_size(layout.box)
	}
	layout.box.lo += desc.margin.xy
	layout.box.hi -= desc.margin.zw

	layout.side = desc.cut_contents_from_side
	layout.bounds = layout.box

	layout.is_dynamic = desc.is_dynamic
	layout.is_root = desc.is_root

	push_options(desc.options)
	push_layout(layout) or_return
	set_cut_size(desc.content_size_option)

	// when ODIN_DEBUG {
	// 	kn.add_box_lines(layout.box, 1, paint = kn.Beige)
	// }

	return true
}

end_layout :: proc() {
	layout := get_current_layout()
	pop_layout()
	pop_options()
	if !layout.is_root {
		next_layout := get_current_layout()

		effective_size := linalg.max(layout.content_size + layout.spacing_size, 0)

		if int(layout.cut_side) > 1 {
			next_layout.content_size.x = max(effective_size.x, next_layout.content_size.x)
			next_layout.content_size.y += effective_size.y
		} else {
			next_layout.content_size.y = max(effective_size.y, next_layout.content_size.y)
			next_layout.content_size.x += effective_size.x
		}
	}
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

shrink :: proc(amount: [4]f32) {
	layout := get_current_layout()
	layout.box.lo += amount.xy
	layout.box.hi -= amount.zw
	layout.spacing_size += (amount.xy + amount.zw)
}

space :: proc(factor: f32 = 1) {
	layout := get_current_layout()
	axis := int(layout.side) / 2
	cut_size := get_current_style().scale * factor //solve_size(get_current_options().size[axis], 0, .Fixed)
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
