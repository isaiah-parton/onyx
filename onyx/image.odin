package draw

import "core:os"

Image :: struct {
	data: rawptr,
	width,
	height,
	channels: int,

	source: [2][2]f32,
	texture_index: int,
}

load_image_from_file :: proc(path: string) -> (index: int, ok: bool) {

	return
}

load_image_from_memory :: proc(data: rawptr, width, height, channels: int) -> (index: int, ok: bool) {

	return
}

load_image :: proc {
	load_image_from_file,
	load_image_from_memory,
}