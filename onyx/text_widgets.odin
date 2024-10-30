package onyx

import "../../vgo"
import "tedit"

Label_Info :: struct {
	using _:     Widget_Info,
	text:        string,
	header:      bool,
	interactive: bool,
	font_size:   Maybe(f32),
	font:        Maybe(vgo.Font),
	color:       Maybe(vgo.Color),
	text_layout: vgo.Text_Layout,
	was_copied:  bool,
}

init_label :: proc(using info: ^Label_Info, loc := #caller_location) -> bool {
	assert(info != nil)
	text_layout = vgo.make_text_layout(
		text,
		font.? or_else core.style.default_font,
		font_size.? or_else core.style.content_text_size,
	)
	desired_size = text_layout.size
	fixed_size = true
	if id == 0 do id = hash(loc)
	self = get_widget(id) or_return
	return true
}

add_label :: proc(using info: ^Label_Info) -> bool {
	assert(info != nil)
	begin_widget(info) or_return
	defer end_widget()

	if self.visible {
		if interactive {
			// draw_text_highlight(text_layout, self.box.lo, core.style.color.accent)
		}
		vgo.fill_text_layout(text_layout, self.box.lo, color.? or_else core.style.color.content)
	}

	return true
}

label :: proc(info: Label_Info, loc := #caller_location) -> Label_Info {
	info := info
	if init_label(&info, loc) {
		add_label(&info)
	}
	return info
}

header :: proc(info: Label_Info, loc := #caller_location) -> Label_Info {
	info := info
	info.font = core.style.header_font
	info.font_size = core.style.header_text_size
	init_label(&info, loc)
	add_label(&info)
	return info
}
