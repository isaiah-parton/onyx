package onyx

Scrollbar_Info :: struct {
	using _: Generic_Widget_Info,
	vertical: bool,
	pos: f32,
	handle_size: f32,
}

Scrollbar_Result :: struct {
	using _: Generic_Widget_Result,
	pos: f32,
}

make_scrollbar :: proc(info: Scrollbar_Info, loc := #caller_location) -> Scrollbar_Info {
	info := info
	info.id = hash(loc)
	info.desired_size[1 - int(info.vertical)] = core.style.shape.scrollbar_thickness
	return info
}

add_scrollbar :: proc(info: Scrollbar_Info) -> (result: Scrollbar_Result) {
	widget, ok := begin_widget(info)
	if !ok do return

	widget.draggable = true
	
	i, j := int(info.vertical), 1 - int(info.vertical)

	rounding := (widget.box.hi[j] - widget.box.lo[j]) / 2

	draw_rounded_box_fill(widget.box, rounding, core.style.color.background)

	handle_box := Box{}

	travel := (widget.box.hi[i] - widget.box.lo[i]) - info.handle_size

	handle_box.lo[i] = widget.box.lo[i] + info.pos * travel
	handle_box.hi[i] = handle_box.lo[i] + info.handle_size

	handle_box.lo[j] = widget.box.lo[j]
	handle_box.hi[j] = widget.box.hi[j]

	draw_rounded_box_fill(handle_box, rounding, core.style.color.substance)

	if point_in_box(core.mouse_pos, handle_box) {
		widget.try_hover = true
	}

	end_widget()
	return
}

do_scrollbar :: proc(info: Scrollbar_Info, loc := #caller_location) -> Scrollbar_Result {
	return add_scrollbar(make_scrollbar(info, loc))
}

Scroll_Zone_Info :: struct {
	using _: Layer_Info,
	no_scroll_x,
	no_scroll_y: bool,
}

begin_scroll_zone :: proc(info: Scroll_Zone_Info, loc := #caller_location) {
	info := info
	info.id = hash(loc)
	info.parent = current_layer().?
	begin_layer(info)
	if !info.no_scroll_x {
		set_side(.Bottom)
		do_scrollbar({})
	}
	if !info.no_scroll_y {
		set_side(.Right)
		do_scrollbar({vertical = true})
	}
}

end_scroll_zone :: proc() {
	end_layer()
}