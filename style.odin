package onyx

import "../vgo"

Color_Scheme :: struct {
	substance, hover, accent, accent_content, content, shadow: vgo.Color,
	field, fg: vgo.Color,
	bg, checker_bg: [2]vgo.Color,
}

Style :: struct {
	// Used as a fallback in case a glyph is not found
	icon_font:      vgo.Font,
	// For code editor
	monospace_font: vgo.Font,
	// Might want a fancy serif font for headers
	header_font:    Maybe(vgo.Font),
	// Default font for everything
	default_font:   vgo.Font,
	// Color scheme should be separate
	color:          Color_Scheme,
	// Dunno why this is its own struct
	using shape:    Style_Shape,
}

Style_Shape :: struct {
	visual_size:         [2]f32,
	header_text_size:    f32,
	default_text_size:   f32,
	tab_text_size:       f32,
	content_text_size:   f32,
	text_input_height:   f32,
	button_height:       f32,
	tooltip_rounding:    f32,
	tooltip_padding:     f32,
	panel_padding:       f32,
	rounding:            f32,
	popup_margin:        f32,
	stroke_width:        f32,
	title_margin:        f32,
	text_padding:        [2]f32,
	menu_padding:        f32,
	scrollbar_thickness: f32,
	table_row_height:    f32,
}

default_style_shape :: proc() -> Style_Shape {
	return Style_Shape {
		tooltip_padding = 3,
		panel_padding = 10,
		text_padding = {6, 4},
		header_text_size = 32,
		default_text_size = 14,
		tab_text_size = 18,
		content_text_size = 16,
		rounding = 4,
		menu_padding = 2,
		popup_margin = 7,
		scrollbar_thickness = 8,
		table_row_height = 40,
		visual_size = {200, 24},
	}
}

light_color_scheme :: proc() -> Color_Scheme {
	return Color_Scheme {
		// background = {255, 255, 255, 255},
		// foreground = {255, 255, 255, 255},
		substance = {162, 167, 167, 255},
		accent = {59, 130, 246, 255},
		accent_content = {25, 25, 25, 255},
		content = {25, 25, 25, 255},
		shadow = {0, 0, 0, 255},
	}
}

dark_color_scheme :: proc() -> Color_Scheme {
	return Color_Scheme {
		bg = {
			{26, 29, 36, 255},
			{37, 41, 52, 255},
		},
		checker_bg = {
			{210, 210, 210, 255},
			{160, 160, 160, 255},
		},
		fg = {50, 53, 68, 255},
		field = {33, 35, 48, 255},
		substance = {105, 109, 125, 255},
		accent = {59, 130, 246, 255},
		accent_content = {0, 0, 0, 255},
		content = {255, 255, 255, 255},
		shadow = {0, 0, 0, 25},
		hover = {120, 125, 140, 95}
	}
}

set_style_rounding :: proc(amount: f32) {
	global_state.style.rounding = amount
}

set_color_scheme :: proc(scheme: Color_Scheme) {
	global_state.style.color = scheme
}