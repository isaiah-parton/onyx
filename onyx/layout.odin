package onyx

import "core:math"
import "core:math/linalg"

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

Layout_Justify :: enum {
	Near,
	Center,
	Far,
}

Layout :: struct {
	original_box:  Box,
	box:           Box,
	justify: Layout_Justify,
	next_cut_side: Side,
	next_align:    Alignment,
	next_padding:  [2]f32,
	next_size:     [2]f32,
	side:          Maybe(Side),
	content_size:  [2]f32,
	spacing_size:  [2]f32,
	fixed:         bool,
	isolated:      bool,
	mode:          Layout_Mode,
}

display_or_add_widget :: proc(widget: ^Widget) {
	layout := current_layout().?
	if layout.justify == .Center {

	} else {

	}
}

push_layout :: proc(layout: Layout) -> bool {
	return push_stack(&global_state.layout_stack, layout)
}

pop_layout :: proc() {
	pop_stack(&global_state.layout_stack)
}

begin_layout_with_options :: proc(side: Side, size: f32) -> bool {
	layout := current_layout().? or_return
	return begin_layout_with_box(cut_box(&layout.box, side, size), side)
}

begin_layout_with_box :: proc(box: Box, side: Side = .Left, isolated: bool = false) -> bool {
	layout := Layout {
		isolated = isolated,
		box = box,
		original_box = box,
	}
	if !layout.isolated {
		if parent_layout, ok := current_layout().?; ok {

			layout.next_cut_side = .Left if int(parent_layout.next_cut_side) > 1 else .Top
		}
	}
	return push_layout(layout)
}

begin_layout :: proc {
	begin_layout_with_box,
	begin_layout_with_options,
}

end_layout :: proc() {
	layout := current_layout().?
	pop_layout()
	if layout.isolated {
		return
	}
	if previous_layout, ok := current_layout().?; ok {
		size := layout.content_size + layout.spacing_size
		if side, ok := layout.side.?; ok {
			if int(side) > 1 {
				previous_layout.content_size.x = max(previous_layout.content_size.x, size.x)
				previous_layout.content_size.y += size.y
			} else {
				previous_layout.content_size.y = max(previous_layout.content_size.y, size.y)
				previous_layout.content_size.x += size.x
			}
		} else {
			add_layout_content_size(previous_layout, size)
		}
	}
}

current_layout :: proc() -> Maybe(^Layout) {
	if global_state.layout_stack.height > 0 {
		return &global_state.layout_stack.items[global_state.layout_stack.height - 1]
	}
	return nil
}

layout_box :: proc() -> Box {
	return current_layout().?.box
}

cut_layout :: proc(layout: ^Layout, side: Maybe(Side) = nil, size: Maybe([2]f32) = nil) -> Box {
	side := side.? or_else layout.next_cut_side
	size := size.? or_else layout.next_size
	box := cut_box(
		&layout.box,
		side,
		next_queued_layout_size(layout).? or_else size[int(side) / 2],
	)
	return box
}

cut_current_layout :: proc(side: Maybe(Side) = nil, size: Maybe([2]f32) = nil) -> Box {
	return cut_layout(current_layout().?, side, size)
}

next_widget_size :: proc(desired_size: [2]f32, fixed: bool = false) -> [2]f32 {
	non_fixed_size :: proc(layout: ^Layout, desired_size: [2]f32) -> [2]f32 {
		if layout.mode == .Maximum {
			return linalg.max(layout.next_size, desired_size)
		} else if layout.mode == .Minimum {
			return linalg.min(layout.next_size, desired_size)
		}
		return layout.next_size
	}
	layout := current_layout().?
	return linalg.min(
		desired_size if fixed else non_fixed_size(layout, desired_size),
		layout.box.hi - layout.box.lo,
	)
}

next_widget_box :: proc(size: [2]f32) -> Box {
	layout := current_layout().?
	box := cut_layout(layout, nil, size)
	if int(layout.next_cut_side) > 1 {
		if size.x < box_width(box) {
			switch layout.next_align {
			case .Near:
				box.hi.x = box.lo.x + size.x
			case .Far:
				box.lo.x = box.hi.x - size.x
			case .Middle:
				break
			}
		}
	} else {
		if size.y < box_height(box) {
			switch layout.next_align {
			case .Near:
				fallthrough
			case .Far:
				fallthrough
			case .Middle:
				box.lo.y = box_center_y(box) - size.y / 2
				box.hi.y = box.lo.y + size.y
			}
		}
	}
	box.lo += layout.next_padding
	box.hi -= layout.next_padding
	return snapped_box(box)
}

set_mode :: proc(mode: Layout_Mode) {
	current_layout().?.mode = mode
}
set_side :: proc(side: Side) {
	layout := current_layout().?
	layout.next_cut_side = side
}
set_width :: proc(width: f32) {
	current_layout().?.next_size.x = width
}
set_width_auto :: proc() {
	current_layout().?.next_size.x = 0
}
set_width_fill :: proc() {
	layout := current_layout().?
	layout.next_size.x = box_width(layout.box)
}
set_width_percent :: proc(width: f32) {
	layout := current_layout().?
	layout.next_size.x = box_width(layout.box) * (width / 100)
}
set_height :: proc(height: f32) {
	current_layout().?.next_size.y = height
}
set_height_auto :: proc() {
	current_layout().?.next_size.y = 0
}
set_height_fill :: proc() {
	layout := current_layout().?
	layout.next_size.y = box_height(layout.box)
}
set_height_percent :: proc(height: f32) {
	layout := current_layout().?
	layout.next_size.y = box_height(layout.box) * (height / 100)
}
set_padding_x :: proc(amount: f32) {
	current_layout().?.next_padding.x = amount
}
set_padding_y :: proc(amount: f32) {
	current_layout().?.next_padding.y = amount
}
set_padding :: proc(amount: f32) {
	current_layout().?.next_padding = amount
}
set_width_to_height :: proc() {
	layout := current_layout().?
	layout.next_size.x = layout.next_size.y
}
set_height_to_width :: proc() {
	layout := current_layout().?
	layout.next_size.y = layout.next_size.x
}

add_padding :: proc(amount: [2]f32) {
	layout := current_layout().?
	layout.box.lo += amount
	layout.box.hi -= amount
	layout.spacing_size += amount * 2
}
add_padding_x :: proc(amount: f32) {
	layout := current_layout().?
	layout.box.lo.x += amount
	layout.box.hi.x -= amount
}
add_padding_y :: proc(amount: f32) {
	layout := current_layout().?
	layout.box.lo.y += amount
	layout.box.hi.y -= amount
}
add_space :: proc(amount: f32) {
	layout := current_layout().?
	cut_box(&layout.box, layout.next_cut_side, amount)
	layout.spacing_size[int(layout.next_cut_side) / 2] += amount
}

layout_is_vertical :: proc(layout: ^Layout) -> bool {
	return int(layout.next_cut_side) > 1
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
