package onyx
// Layouts are stackable data structures for cutting boxes.
// 	They need to be able to store their contents' desired sizes for the next frame
//  but also be isolated in some cases so that this doesn't happen.
//
// 	`content_size` is the accumulative size of contained widgets and layouts.
//
//  `spacing_size' is the accumulative size of spacing and is separated because it
// 	is treated differently.
//
// 	TODO: Add a separate field for total cut size that disregards desired size
import "core:math"
import "core:math/linalg"
Layout_Mode :: enum {
	Maximum,
	Minimum,
	Absolute,
}
// Info for creating a layout
Layout_Info :: struct {
	// If defined, the layout will occupy the given box
	box:      Maybe(Box),
	// Otherwise, it will be cut from the previous layout with these parameters
	side:     Maybe(Side),
	size:     Maybe(f32),
	// Isolate this layout?
	isolated: bool,
}
// The internal layout structure
Layout :: struct {
	// The bounding box (also the layout's box in its original state)
	bounds:        Box,
	// The current box to cut from
	box:           Box,
	// Parameters for cutting the layout
	next_cut_side: Side,
	next_align:    Alignment,
	next_padding:  [2]f32,
	next_size:     [2]f32,
	size_queue:    [100]f32,
	queue_len:     int,
	queue_offset:  int,
	// Side from which the layout was cut when created
	side:          Maybe(Side),
	// Store accumulative size for next frame
	content_size:  [2]f32,
	spacing_size:  [2]f32,
	// When true, only exact sizes are accumulated
	// instead of desired sizes
	fixed:         bool,
	// Isolated from previous layout?
	isolated:      bool,
	mode: Layout_Mode,
}
// Queue the next size to be cut from this layout
queue_layout_size :: proc(layout: ^Layout, size: f32) {
	layout.size_queue[layout.queue_len] = size
	layout.queue_len += 1
}
// Get the next cut size that was previously queued on this layout
next_queued_layout_size :: proc(layout: ^Layout) -> Maybe(f32) {
	if layout.queue_offset < layout.queue_len {
		result := layout.size_queue[layout.queue_offset]
		layout.queue_offset += 1
		return result
	}
	return nil
}
// Push a new layout to the global stack
push_layout :: proc(layout: Layout) -> bool {
	return push_stack(&core.layout_stack, layout)
}
// Pop the last layout from the global stack
pop_layout :: proc() {
	pop_stack(&core.layout_stack)
}
// Begin a layout
begin_layout :: proc(info: Layout_Info) -> bool {
	layout := Layout {
		isolated      = info.isolated,
		side          = info.side,
	}
	if last_layout, ok := current_layout().?; ok {
		side := info.side.? or_else last_layout.next_cut_side
		size := info.size.? or_else last_layout.next_size[int(side) / 2]
		layout.box = info.box.? or_else cut_box(&last_layout.box, side, size)
		layout.next_size     = last_layout.next_size
		layout.next_padding  = last_layout.next_padding
		layout.next_cut_side = .Left if int(side) > 1 else .Top
	} else {
		layout.box = info.box.? or_return
	}
	layout.bounds = layout.box
	return push_layout(layout)
}
// End the current layout
end_layout :: proc() {
	layout := current_layout().?
	pop_layout()
	// If this layout is isolated we quit early
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
// Scoped layout proc
@(deferred_out = __layout)
layout :: proc(info: Layout_Info) -> (ok: bool) {
	return begin_layout(info)
}
@(private)
__layout :: proc(ok: bool) {
	if ok {
		end_layout()
	}
}
// Get the current layout if there is one, otherwise returns `nil`
current_layout :: proc() -> Maybe(^Layout) {
	if core.layout_stack.height > 0 {
		return &core.layout_stack.items[core.layout_stack.height - 1]
	}
	return nil
}
// Get the current layout box.  **Asserts that there is a layout.**
layout_box :: proc() -> Box {
	return current_layout().?.box
}
// Cut this layout with these parameters
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
// Calls `cut_layout` on the current layout.  **Assertive**
cut_current_layout :: proc(side: Maybe(Side) = nil, size: Maybe([2]f32) = nil) -> Box {
	return cut_layout(current_layout().?, side, size)
}
// Get the next widget box
// TODO: Rename this as it isn't used exclusively for singular widgets
next_widget_box :: proc(info: ^Widget_Info) -> Box {
	non_fixed_size :: proc(layout: ^Layout, desired_size: [2]f32) -> [2]f32 {
		if layout.mode == .Maximum {
			return linalg.max(layout.next_size, desired_size)
		} else if layout.mode == .Minimum {
			return linalg.min(layout.next_size, desired_size)
		}
		return layout.next_size
	}
	// First assert that a layout exists
	layout := current_layout().?
	// Decide the size of the box
	size: [2]f32
	if info != nil {
		size = linalg.min(
			info.desired_size if info.fixed_size else non_fixed_size(layout, info.desired_size),
			layout.box.hi - layout.box.lo,
		)
	} else {
		size = linalg.min(layout.next_size, layout.box.hi - layout.box.lo)
	}
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

// Procedures for setting the cut parameters of the current layout
// **These are all assertive**
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

// Procedures that directly modify the current layout
// **These are all assertive**

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
add_space :: proc(amount: f32) {
	layout := current_layout().?
	cut_box(&layout.box, layout.next_cut_side, amount)
	layout.spacing_size[int(layout.next_cut_side) / 2] += amount
}

// Is this layout vertical
layout_is_vertical :: proc(layout: ^Layout) -> bool {
	return int(layout.next_cut_side) > 1
}
// Add content size to this layout
add_layout_content_size :: proc(layout: ^Layout, size: [2]f32) {
	if layout_is_vertical(layout) {
		layout.content_size.x = max(layout.content_size.x, size.x)
		layout.content_size.y += size.y
	} else {
		layout.content_size.y = max(layout.content_size.y, size.y)
		layout.content_size.x += size.x
	}
}
