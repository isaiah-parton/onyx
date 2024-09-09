package onyx

Label_Info :: struct {
	using _:    Generic_Widget_Info,
	font_style: Font_Style,
	font_size:  f32,
	text:       string,
	__text_job: Text_Job,
}

make_label :: proc(info: Label_Info, loc := #caller_location) -> Label_Info {
	info := info
	info.id = hash(loc)
	info.__text_job, _ = make_text_job(
		{
			text = info.text,
			size = info.font_size,
			font = core.style.fonts[info.font_style],
			align_h = .Left,
			align_v = .Top,
		},
	)
	info.fixed_size = true
	info.desired_size = info.__text_job.size
	return info
}

add_label :: proc(info: Label_Info) {
	widget, ok := begin_widget(info)
	if !ok do return

	if widget.visible {
		draw_text_glyphs(info.__text_job, widget.box.lo, core.style.color.content)
	}

	end_widget()
}

do_label :: proc(info: Label_Info, loc := #caller_location) {
	add_label(make_label(info, loc))
}
