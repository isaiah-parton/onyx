package ui

// Layout
Layout :: struct {
	box: Box,
	content_side: Side,
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

begin_layout_cut :: proc(side: Side, size: f32, content_side: Side) {
	layout := current_layout()
	push_layout(Layout{
		box = cut_box(&layout.box, side, size),
		content_side = content_side,
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
	layout.content_side = side
}

padding :: proc(amount: f32) {
	layout := current_layout()
	layout.box = shrink_box(layout.box, amount)
}

space :: proc(amount: f32) {
	layout := current_layout()
	cut_box(&layout.box, layout.content_side, amount)
}