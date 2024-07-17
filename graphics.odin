package ui

import "vendor:fontstash"

Color :: [4]u8
Vertex :: struct {
	pos: [2]f32,
	uv: [2]f32,
	col: [4]u8,
}
Draw_State :: struct {
	font: int,
}

draw_box_fill :: proc(box: Box, color: Color) {

}