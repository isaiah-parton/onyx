package ui

Breadcrumb_Info :: struct {
	using _: Generic_Widget_Info,
	text: string,
	is_tail: bool,
}

Breadcrumb_Result :: struct {
	using _: Generic_Widget_Result,
}

make_breadcrumb :: proc(info: Breadcrumb_Info, loc := #caller_location) -> Breadcrumb_Info {
	info := info
	info.id = hash(loc)
	text_options := Text_Options{
		font = core.style.fonts[.Regular],
		size = core.style.header_text_size,
	}
	text_size := measure_text({
		text = info.text,
		options = text_options,
	})
	info.desired_size = text_size
	if !info.is_tail {
		info.desired_size += 15
	}
	info.fixed_size = true
	return info
}

display_breadcrumb :: proc(info: Breadcrumb_Info) -> (result: Breadcrumb_Result) {
	widget := get_widget(info)
	widget.box = next_widget_box(info)
	context.allocator = widget.allocator
	result.self = widget

	if widget.visible {
		draw_text(widget.box.low, {
			text = info.text,
			options = Text_Options{
				font = core.style.fonts[.Regular],
				size = core.style.header_text_size,
			},
		}, core.style.color.content)
		if info.is_tail {
			draw_aligned_rune(core.style.fonts[.Bold], 20, '>', {widget.box.high.x, box_center_y(widget.box)}, core.style.color.substance, .Right, .Middle)
		}
	}

	return
}
