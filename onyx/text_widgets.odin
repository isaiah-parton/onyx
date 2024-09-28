package onyx

Label_Info :: struct {
	using _:             Widget_Info,
	text:                string,
	font_style:          Maybe(Font_Style),
	font_size:           Maybe(f32),
	text_job:            Text_Job,
	copied_to_clipboard: bool,
}

init_label :: proc(info: ^Label_Info, loc := #caller_location) -> Label_Info {
	assert(info != nil)
	info.id = hash(loc)
	info.__text_job, _ = make_text_job(
		{
			text = info.text,
			size = info.font_size.? or_else core.style.header_text_size,
			font = core.style.fonts[info.font_style.? or_else .Bold],
			align_h = .Left,
			align_v = .Top,
		},
	)
	info.fixed_size = true
	info.desired_size = info.__text_job.size
	return info
}

add_label :: proc(info: ^Label_Info) {
	assert(info != nil)
	widget, ok := begin_widget(&info); if !ok do return
	defer end_widget()

	if widget.visible {
		draw_text_glyphs(
			info.__text_job,
			widget.box.lo,
			core.style.color.content,
		)
	}
}

label :: proc(
	info: Label_Info,
	loc := #caller_location,
) -> Label_Info {
	info := info
	init_label(&info, loc)
	add_label(&label)
	return info
}
