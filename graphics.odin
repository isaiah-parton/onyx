package ui

import "core:fmt"
import "vendor:fontstash"

Color :: [4]u8
Image ::struct {
	width, height: int,
	data: []u8,
	channels: int,
}
Vertex :: struct {
	pos: [2]f32,
	uv: [2]f32,
	col: [4]u8,
}
Draw_State :: struct {
	font: int,
}
Draw_Surface :: struct {
	vertices: [dynamic]Vertex,
	indices: [dynamic]u16,
}

destroy_image :: proc(using self: ^Image) {
	delete(data)
}

init_draw_surface :: proc(surface: ^Draw_Surface) {
	reserve(&surface.vertices, 65536)
	reserve(&surface.indices, 65536)
}
make_draw_surface :: proc() -> Draw_Surface {
	res: Draw_Surface
	init_draw_surface(&res)
	return res
}

__get_draw_surface :: proc() -> ^Draw_Surface {
	return core.draw_surface
}

draw_box_fill :: proc(box: Box, color: Color) {
	if core.draw_surface == nil {
		return
	}
	i := len(core.draw_surface.vertices)
	append(&core.draw_surface.vertices, 
		Vertex{pos = box.low, col = color},
		Vertex{pos = {box.low.x, box.high.y}, col = color},
		Vertex{pos = box.high, col = color},
		Vertex{pos = {box.high.x, box.low.y}, col = color},
		)
	append(&core.draw_surface.indices,
		u16(i),
		u16(i + 1),
		u16(i + 2),
		u16(i),
		u16(i + 2),
		u16(i + 3),
		)
}