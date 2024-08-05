package onyx

import "../draw"

Label_Info :: struct {
	using _: Generic_Widget_Info,
	font_style: Font_Style,
	font_size: f32,
	text: string,

	__text_info: draw.Text_Info,
}

make_label :: proc(info: Label_Info, loc := #caller_location) -> Label_Info {
	info := info
	info.id = hash(loc)
	info.__text_info = Text_Info{
		text = info.text,
		size = info.font_size,
		font = core.style.fonts[info.font_style],
		align_h = .Left,
		align_v = .Top,
	}
	info.fixed_size = true
	info.desired_size = draw.measure_text(info.__text_info)
	return info
}

display_label :: proc(info: Label_Info) {
	widget := get_widget(info)
	widget.box = next_widget_box(info)

	if widget.visible {
		draw_text(widget.box.low, info.__text_info, core.style.color.content)
	}
}

do_label :: proc(info: Label_Info) {
	display_label(make_label(info))
}