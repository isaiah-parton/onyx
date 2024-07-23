package ui

Color_Scheme :: struct {
	background,
	foreground,
	substance,
	accent,
	content: Color,
}
Style :: struct {
	font: int,
	color: Color_Scheme,

	header_text_size,
	button_text_size,
	content_text_size: f32,
	
	tooltip_rounding,
	tooltip_padding,
	panel_rounding,
	rounding: f32,
	
	stroke_width: f32,
	title_margin: f32,
	title_padding: f32,
	panel_background_opacity: f32,
}

light_color_scheme :: proc() -> Color_Scheme {
	return Color_Scheme{
		background = {0, 0, 0, 255},
		foreground = {25, 25, 32, 255},
		substance = {65, 65, 75, 255},
		accent = {59, 130, 246, 255},
		content = {255, 255, 255, 255},
	}
}
dark_color_scheme :: proc() -> Color_Scheme {
	return Color_Scheme{
		background = {0, 0, 0, 255},
		foreground = {25, 25, 32, 255},
		substance = {65, 65, 75, 255},
		accent = {59, 130, 246, 255},
		content = {255, 255, 255, 255},
	}
}

set_style_font :: proc(path: string) -> bool {
	core.style.font = load_font(path) or_return
	return true
}

set_style_rounding :: proc(amount: f32) {
	core.style.rounding = amount
}

set_color_scheme :: proc(scheme: Color_Scheme) {
	core.style.color = scheme
}