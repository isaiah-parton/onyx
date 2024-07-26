package ui

// Layout
Layout :: struct {
	box: Box,
	next_side: Side,
	next_size: f32,
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

next_widget_box :: proc() -> Box {
	layout := current_layout()
	return cut_box(&layout.box, layout.next_side, layout.next_size)
}

push_layout :: proc(layout: Layout) {
	push(&core.layout_stack, layout)
}

pop_layout :: proc() {
	pop(&core.layout_stack)
}

begin_layout_box :: proc(box: Box) {
	push_layout(Layout{
		box = box,
	})
}

begin_layout_cut :: proc(side: Side, size: f32, next_side: Side) {
	layout := current_layout()
	push_layout(Layout{
		box = cut_box(&layout.box, side, size),
		next_side = next_side,
	})
}

begin_layout :: proc {
	begin_layout_cut,
	begin_layout_box,
}

end_layout :: proc() {
	pop_layout()
}

side :: proc(side: Side) {
	layout := current_layout()
	layout.next_side = side
}

size :: proc(size: f32) {
	current_layout().next_size = size
}

padding :: proc(amount: f32) {
	layout := current_layout()
	layout.box = shrink_box(layout.box, amount)
}

space :: proc(amount: f32) {
	layout := current_layout()
	cut_box(&layout.box, layout.next_side, amount)
}