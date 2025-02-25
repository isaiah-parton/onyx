package ronin

import kn "local:katana"

Color_Scheme :: struct {
	button, button_background, hover, accent, accent_content, content, shadow: kn.Color,
	field, foreground, foreground_stroke, foreground_accent, background:       kn.Color,
	grid_background, grid_minor_lines, grid_major_lines:                       kn.Color,
	checkers0, checkers1:                                                      kn.Color,
}

Style :: struct {
	icon_font:      kn.Font,
	monospace_font: kn.Font,
	header_font:    Maybe(kn.Font),
	default_font:   kn.Font,
	bold_font:      kn.Font,
	color:          Color_Scheme,
	using shape:    Style_Shape,
}

Style_Shape :: struct {
	scale:               f32,
	header_text_size:    f32,
	default_text_size:   f32,
	tab_text_size:       f32,
	icon_size:           f32,
	content_text_size:   f32,
	text_input_height:   f32,
	button_height:       f32,
	tooltip_rounding:    f32,
	tooltip_padding:     f32,
	panel_padding:       f32,
	rounding:            f32,
	popup_margin:        f32,
	line_width:        f32,
	title_margin:        f32,
	text_padding:        [2]f32,
	menu_padding:        f32,
	scrollbar_thickness: f32,
	table_row_height:    f32,
}

get_current_style :: proc() -> ^Style {
	return &global_state.style
}

rounded_corners :: proc(corners: Corners) -> [4]f32 {
	return {
		global_state.style.rounding * f32(i32(.Top_Left in corners)),
		global_state.style.rounding * f32(i32(.Top_Right in corners)),
		global_state.style.rounding * f32(i32(.Bottom_Left in corners)),
		global_state.style.rounding * f32(i32(.Bottom_Right in corners)),
	}
}

default_style_shape :: proc() -> Style_Shape {
	return Style_Shape {
		tooltip_padding = 3,
		line_width = 2,
		panel_padding = 10,
		text_padding = {6, 4},
		header_text_size = 22,
		default_text_size = 14,
		tab_text_size = 18,
		content_text_size = 14,
		icon_size = 20,
		rounding = 4,
		menu_padding = 4,
		popup_margin = 7,
		scrollbar_thickness = 8,
		table_row_height = 40,
		scale = 15,
	}
}

light_color_scheme :: proc() -> Color_Scheme {
	return Color_Scheme {
		button = {190, 198, 193, 255},
		button_background = {228, 230, 227, 255},
		hover = {120, 125, 140, 255},
		accent = {0, 127, 255, 255},
		accent_content = {10, 10, 10, 255},
		content = {0, 0, 0, 255},
		shadow = {0, 0, 0, 10},
		field = {233, 234, 232, 255},
		foreground = {255, 255, 255, 255},
		foreground_stroke = {180, 180, 180, 255},
		foreground_accent = {30, 30, 30, 255},
		background = {240, 240, 240, 255},
		grid_background = {240, 240, 240, 255},
		grid_minor_lines = {255, 255, 255, 255},
		grid_major_lines = {26, 181, 111, 255},
		checkers0 = {210, 210, 210, 255},
		checkers1 = {160, 160, 160, 255},
	}
}

dark_color_scheme :: proc() -> Color_Scheme {
	return Color_Scheme {
		checkers0 = {210, 210, 210, 255},
		checkers1 = {160, 160, 160, 255},
		background = {8, 8, 8, 255},
		foreground = {18, 19, 20, 255},
		foreground_stroke = {60, 60, 60, 255},
		foreground_accent = {30, 30, 30, 255},
		grid_background = {0, 0, 0, 255},
		grid_minor_lines = {16, 15, 17, 255},
		grid_major_lines = {45, 45, 150, 255},
		field = {8, 8, 8, 255},
		button = {67, 65, 69, 255},
		button_background = {40, 38, 42, 255},
		accent = {34, 117, 34, 255},
		accent_content = {10, 10, 10, 255},
		content = {255, 255, 255, 255},
		shadow = {0, 0, 0, 75},
		hover = {120, 125, 140, 95},
	}
}

hstack_corner_radius :: proc(index, count: int) -> [4]f32 {
	if index == 0 {
		return {1, 0, 1, 0}
	}
	if index == count - 1 {
		return {0, 1, 0, 1}
	}
	return 0
}

vstack_corner_radius :: proc(index, count: int) -> [4]f32 {
	if index == 0 {
		return {1, 1, 0, 0}
	}
	if index == count - 1 {
		return {0, 0, 1, 1}
	}
	return 0
}

hstack_corners :: proc(index, count: int) -> Corners {
	if index == 0 {
		return {.Top_Left, .Bottom_Left}
	}
	if index == count - 1 {
		return {.Top_Right, .Bottom_Right}
	}
	return {}
}

vstack_corners :: proc(index, count: int) -> Corners {
	if index == 0 {
		return {.Top_Left, .Top_Right}
	}
	if index == count - 1 {
		return {.Bottom_Left, .Bottom_Right}
	}
	return {}
}

set_style_rounding :: proc(amount: f32) {
	global_state.style.rounding = amount
}

set_color_scheme :: proc(scheme: Color_Scheme) {
	get_current_style().color = scheme
}
