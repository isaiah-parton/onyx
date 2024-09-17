package onyx

import "core:math"
import "core:math/linalg"

Layout_Info :: struct {
	box:        Maybe(Box),
	side:       Maybe(Side),
	size:       Maybe(f32),
}

// Layout
// Next size = `content_sizes[content_index]`
Layout :: struct {
	bounds, box: Box,
	// Side from which new content is cut
	next_cut_side:     Side,
	next_align:        Alignment,
	next_padding:      [2]f32,
	next_size:         [2]f32,
	size_queue:        [100]f32,
	queue_len:         int,
	queue_offset:      int,
	// Side from which the layout was cut
	side:              Maybe(Side),
	// Store accumulative size for next frame
	content_size:      [2]f32,
	spacing_size:      [2]f32,
	// When true, only exact sizes are accumulated
	// instead of desired sizes
	fixed: bool,
	// Isolated from previous layout?
	isolated: bool,
	// Attachments
	table_info:        Maybe(Table_Info),
}

queue_layout_size :: proc(layout: ^Layout, size: f32) {
	layout.size_queue[layout.queue_len] = size
	layout.queue_len += 1
}

next_queued_layout_size :: proc(layout: ^Layout) -> Maybe(f32) {
	if layout.queue_offset < layout.queue_len {
		result := layout.size_queue[layout.queue_offset]
		layout.queue_offset += 1
		return result
	}
	return nil
}

push_layout :: proc(layout: Layout) -> bool {
	return push_stack(&core.layout_stack, layout)
}

pop_layout :: proc() {
	pop_stack(&core.layout_stack)
}

begin_layout :: proc(info: Layout_Info) -> bool {
	last_layout := current_layout().?
	side := info.side.? or_else last_layout.next_cut_side
	size := info.size.? or_else last_layout.next_size[int(side) / 2]
	box := info.box.? or_else cut_box(&last_layout.box, side, size)
	layout := Layout {
		box           = box,
		bounds  = box,
		side          = info.side,
		next_cut_side = .Left if int(side) > 1 else .Top,
		next_size     = last_layout.next_size,
		next_padding  = last_layout.next_padding,
	}
	return push_layout(layout)
}

end_layout :: proc() {
	layout := current_layout().?
	pop_layout()

	if layout.isolated {
		return
	}

	// Update previous layout's content size
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

@(deferred_out = __do_layout)
do_layout :: proc(info: Layout_Info) -> (ok: bool) {
	return begin_layout(info)
}

@(private)
__do_layout :: proc(ok: bool) {
	if ok {
		end_layout()
	}
}

current_layout :: proc() -> Maybe(^Layout) {
	if core.layout_stack.height > 0 {
		return &core.layout_stack.items[core.layout_stack.height - 1]
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

next_widget_box :: proc(info: Generic_Widget_Info) -> Box {
	// First assert that a layout exists
	layout := current_layout().?
	// Decide the size of the box
	size := linalg.min(
		(info.desired_size if info.fixed_size else linalg.max(layout.next_size, info.desired_size)),
		layout.box.hi - layout.box.lo,
	)
	// Cut the initial box
	box := cut_layout(layout, nil, size)
	if layout.queue_offset > 0 {
		size = box_size(box)
	}
	// Account for alignment if the content is smaller than the cut box
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
	// Apply padding
	box.lo += layout.next_padding
	box.hi -= layout.next_padding
	// Result is rounded for pixel perfect rendering
	return {linalg.floor(box.lo), linalg.floor(box.hi)}
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

shrink :: proc(amount: f32) {
	layout := current_layout().?
	layout.box.lo += amount
	layout.box.hi -= amount
	layout.spacing_size += amount * 2
}

shrink_x :: proc(amount: f32) {
	layout := current_layout().?
	layout.box.lo.x += amount
	layout.box.hi.x -= amount
}

shrink_y :: proc(amount: f32) {
	layout := current_layout().?
	layout.box.lo.y += amount
	layout.box.hi.y -= amount
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
