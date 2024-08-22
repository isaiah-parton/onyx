package onyx

Color_Scheme :: struct {
	background, foreground, substance, accent, accent_content, content: Color,
}

Font_Style :: enum {
	Light,
	Regular,
	Medium,
	Bold,
	Icon,
	Monospace,
}

Style :: struct {
	fonts:       [Font_Style]int,
	color:       Color_Scheme,
	using shape: Style_Shape,
}

Style_Shape :: struct {
	header_text_size, button_text_size, tab_text_size, content_text_size: f32,
	text_input_height, button_height:                                     f32,
	tooltip_rounding, tooltip_padding, panel_padding, rounding:           f32,
	stroke_width:                                                         f32,
	title_margin:                                                         f32,
	title_padding:                                                        f32,
	menu_padding:                                                         f32,
	scrollbar_thickness:                                                  f32,
	rounded_scrollbars:                                                   bool,
}

default_style_shape :: proc() -> Style_Shape {
	return Style_Shape {
		tooltip_padding = 3,
		panel_padding = 10,
		header_text_size = 26,
		button_text_size = 18,
		tab_text_size = 18,
		content_text_size = 18,
		rounding = 0,
		menu_padding = 5,
		scrollbar_thickness = 10,
	}
}

light_color_scheme :: proc() -> Color_Scheme {
	return Color_Scheme {
		background = {0, 0, 0, 255},
		foreground = {25, 25, 32, 255},
		substance = {65, 65, 75, 255},
		accent = {59, 130, 246, 255},
		accent_content = {255, 255, 255, 255},
		content = {255, 255, 255, 255},
	}
}

dark_color_scheme :: proc() -> Color_Scheme {
	return Color_Scheme {
		background = {0, 0, 0, 255},
		foreground = {15, 15, 15, 255},
		substance = {40, 42, 45, 255},
		accent = {234, 88, 12, 255},
		accent_content = {255, 255, 255, 255},
		content = {255, 255, 255, 255},
	}
}

set_style_font :: proc(style: Font_Style, path: string) -> bool {
	core.style.fonts[style] = load_font(path) or_return
	return true
}

set_style_rounding :: proc(amount: f32) {
	core.style.rounding = amount
}

set_color_scheme :: proc(scheme: Color_Scheme) {
	core.style.color = scheme
}
