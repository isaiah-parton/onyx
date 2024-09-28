package onyx

Label_Info :: struct {
	using _:             Widget_Info,
	text:                string,
	font_style:          Maybe(Font_Style),
	font_size:           Maybe(f32),
	text_job:            Text_Job,
	copied_to_clipboard: bool,
}

init_label :: proc(info: ^Label_Info, loc := #caller_location) -> bool {
	assert(info != nil)
	info.id = hash(loc)
	info.self = get_widget(info.id.?) or_return
	info.text_job, _ = make_text_job(
		{
			text = info.text,
			size = info.font_size.? or_else core.style.header_text_size,
			font = core.style.fonts[info.font_style.? or_else .Bold],
			align_h = .Left,
			align_v = .Top,
		},
	)
	info.fixed_size = true
	info.desired_size = info.text_job.size
	return true
}

add_label :: proc(using info: ^Label_Info) -> bool {
	assert(info != nil)
	begin_widget(info) or_return
	defer end_widget()

	if self.visible {
		draw_text_glyphs(text_job, self.box.lo, core.style.color.content)
	}

	return true
}

label :: proc(info: Label_Info, loc := #caller_location) -> Label_Info {
	info := info
	init_label(&info, loc)
	add_label(&info)
	return info
}
