package onyx

Color_Scheme :: struct {
	background, foreground, substance, accent, accent_content, content, shadow: Color,
}

Style :: struct {
	// Used as a fallback in case a glyph is not found
	icon_font: int,
	// For code editor
	monospace_font: int,
	// Might want a fancy serif font for headers
	header_font: Maybe(int),
	// Default font for everything
	default_font: int,
	// Color scheme should be separate
	color:       Color_Scheme,
	// Dunno why this is its own struct
	using shape: Style_Shape,
}

Style_Shape :: struct {
	visual_size:                                                          [2]f32,
	header_text_size, button_text_size, tab_text_size, content_text_size: f32,
	text_input_height, button_height:                                     f32,
	tooltip_rounding, tooltip_padding, panel_padding, rounding:           f32,
	popup_margin: f32,
	stroke_width:                                                         f32,
	title_margin:                                                         f32,
	text_padding:                                                        [2]f32,
	menu_padding:                                                         f32,
	scrollbar_thickness:                                                  f32,
	table_row_height:                                                     f32,
}

default_style_shape :: proc() -> Style_Shape {
	return Style_Shape {
		tooltip_padding = 4,
		panel_padding = 10,
		text_padding = {7, 5},
		header_text_size = 36,
		button_text_size = 18,
		tab_text_size = 18,
		content_text_size = 18,
		rounding = 5,
		menu_padding = 2,
		popup_margin = 7,
		scrollbar_thickness = 8,
		table_row_height = 40,
		visual_size = {200, 30},
	}
}

light_color_scheme :: proc() -> Color_Scheme {
	return Color_Scheme {
		background = {255, 255, 255, 255},
		foreground = {255, 255, 255, 255},
		substance = {162, 167, 167, 255},
		accent = {59, 130, 246, 255},
		accent_content = {25, 25, 25, 255},
		content = {25, 25, 25, 255},
		shadow = {0, 0, 0, 40},
	}
}

dark_color_scheme :: proc() -> Color_Scheme {
	return Color_Scheme {
		background = {12, 10, 17, 255},
		foreground = {25, 24, 32, 255},
		substance = {55, 55, 60, 255},
		accent = {59, 130, 246, 255},
		accent_content = {255, 255, 255, 255},
		content = {255, 255, 255, 255},
		shadow = {0, 0, 0, 40},
	}
}

set_style_rounding :: proc(amount: f32) {
	core.style.rounding = amount
}

set_color_scheme :: proc(scheme: Color_Scheme) {
	core.style.color = scheme
}
