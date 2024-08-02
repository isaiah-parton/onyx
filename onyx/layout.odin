package ui

import "core:math"
import "core:math/linalg"

Layout_Info :: struct {
	box: Maybe(Box),
	side: Side,
	size: f32,
	show_lines: bool,
}

// Layout
Layout :: struct {
	original_box,				// Original box
	box: Box,						// Current box to cut from
	next_side: Side,		// Next side to cut from
	next_size: [2]f32,	// Next cut size

	show_lines: bool,		
	side: Maybe(Side),	// What side was the layout cut from (if it was cut)
}

Side :: enum {
	Top,
	Bottom,
	Left,
	Right,
}

current_layout :: proc(loc := #caller_location) -> ^Layout {
	assert(core.layout_stack.height > 0, "There is no current layout", loc)
	return &core.layout_stack.items[core.layout_stack.height - 1]
}

layout_box :: proc() -> Box {
	return current_layout().box
}

cut_layout :: proc(layout: ^Layout, side: Maybe(Side) = nil, size: Maybe([2]f32) = nil) -> Box {
	side := side.? or_else layout.next_side
	size := size.? or_else layout.next_size
	box := cut_box(&layout.box, side, size[1 - int(side) / 2])
	return box
}

next_widget_box :: proc(info: Generic_Widget_Info) -> Box {
	layout := current_layout()
	size := linalg.min(linalg.max(layout.next_size, info.desired_size), layout.box.high - layout.box.low)
	box := cut_layout(layout, nil, size)
	if int(layout.next_side) > 1 {
		if size.y < box_height(box) {
			box.low.y = box_center_y(box) - size.y / 2
			box.high.y = box.low.y + size.y
		}
	} else {
		if size.x < box_width(box) {
			box.high.x = box.low.x + size.x
		}
	}
	return {
		linalg.floor(box.low),
		linalg.floor(box.high),
	}
}

push_layout :: proc(layout: Layout) {
	push(&core.layout_stack, layout)
}

pop_layout :: proc() {
	pop(&core.layout_stack)
}

begin_layout :: proc(info: Layout_Info) {
	box := info.box.? or_else cut_layout(current_layout(), info.side, info.size)
	layout := Layout{
		box = box,
		original_box = box,
		side = info.side,
		show_lines = info.show_lines,
		next_side = .Left if int(info.side) < 2 else .Top,
	}
	push_layout(layout)
}

end_layout :: proc() {
	layout := current_layout()
	pop_layout()
	if layout.show_lines {
		if side, ok := layout.side.?; ok {
			box := layout.original_box
			switch layout.side {
				case .Top:
				draw_box_fill({box.low, {box.high.x, box.low.y + 1}}, core.style.color.substance)
				case .Bottom:
				draw_box_fill({{box.low.x, box.high.y - 1}, box.high}, core.style.color.substance)
				case .Left:
				draw_box_fill({{box.high.x - 1, box.low.y}, box.high}, core.style.color.substance)
				case .Right:
				draw_box_fill({box.low, {box.low.x + 1, box.high.y}}, core.style.color.substance)
			}
		}
	}
}

side :: proc(side: Side) {
	layout := current_layout()
	layout.next_side = side
}

set_width :: proc(width: f32) {
	current_layout().next_size.x = width
}
set_width_auto :: proc() {
	current_layout().next_size.x = 0
}
set_width_fill :: proc() {
	layout := current_layout()
	layout.next_size.x = box_width(layout.box)
}
set_width_percent :: proc(width: f32) {
	layout := current_layout()
	layout.next_size.x = box_width(layout.box) * (width / 100)
}
set_height :: proc(height: f32) {
	current_layout().next_size.y = height
}
set_height_auto :: proc() {
	current_layout().next_size.y = 0
}
set_height_fill :: proc() {
	layout := current_layout()
	layout.next_size.y = box_height(layout.box)
}
set_height_percent :: proc(height: f32) {
	layout := current_layout()
	layout.next_size.y = box_height(layout.box) * (height / 100)
}

shrink :: proc(amount: f32) {
	layout := current_layout()
	layout.box.low += amount
	layout.box.high -= amount
}

shrink_x :: proc(amount: f32) {
	layout := current_layout()
	layout.box.low.x += amount
	layout.box.high.x -= amount
}

shrink_y :: proc(amount: f32) {
	layout := current_layout()
	layout.box.low.y += amount
	layout.box.high.y -= amount
}

space :: proc(amount: f32) {
	layout := current_layout()
	cut_box(&layout.box, layout.next_side, amount)
}