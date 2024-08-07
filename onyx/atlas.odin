package onyx

import "core:slice"
import "core:fmt"
import "core:mem"
import "core:math"
import "core:math/linalg"

import sg "extra:sokol-odin/sokol/gfx"

Atlas :: struct {
	using image: Image,

	data: []u8,

	offset: [2]f32,
	row_height: f32,

	full,
	modified: bool,
}

init_atlas :: proc(atlas: ^Atlas, width, height: int) {
	atlas.width, atlas.height = width, height
	atlas.data = make([]u8, width * height * 4)
	atlas.data[0] = 255
	atlas.data[1] = 255
	atlas.data[2] = 255
	atlas.data[3] = 255
	atlas.offset = {1, 1}
	atlas._image = sg.make_image(sg.Image_Desc{
		width = i32(width),
		height = i32(height),
		usage = .DYNAMIC,
		pixel_format = .RGBA8,
		data = {
			subimage = {
				0 = {
					0 = {
						ptr = raw_data(atlas.data),
						size = u64(len(atlas.data)),
					},
				},
			},
		},
	})
}

destroy_atlas :: proc(atlas: ^Atlas) {
	sg.destroy_image(atlas.image)
	delete(atlas.data)
}

update_atlas :: proc(atlas: ^Atlas) {
	sg.update_image(atlas.image, {
		subimage = {
			0 = {
				0 = {
					ptr = raw_data(atlas.data),
					size = u64(len(atlas.data)),
				},
			},
		},
	})
}

add_glyph_to_atlas :: proc(data: [^]u8, width, height: int, atlas: ^Atlas) -> Box {
	box := get_next_atlas_box(atlas, {f32(width), f32(height)})

	pixel_size: int = 4

	for y in 0..<height {
		target_row_offset := (y + int(box.lo.y)) * atlas.width * pixel_size
		source_row_offset := y * width
		for x in 0..<width {
			target_offset := target_row_offset + (x + int(box.lo.x)) * pixel_size
			atlas.data[target_offset] = 255
			atlas.data[target_offset + 1] = 255
			atlas.data[target_offset + 2] = 255
			atlas.data[target_offset + 3] = data[source_row_offset + x]
		}
	}
	atlas.modified = true
	return box
}

reset_atlas :: proc(atlas: ^Atlas) -> bool {
	width, height := atlas.width, atlas.height
	destroy_atlas(atlas)
	init_atlas(atlas, width, height)
	atlas.full = false

	return true
}

get_next_atlas_box :: proc(atlas: ^Atlas, size: [2]f32) -> (box: Box) {

	if atlas.offset.x + size.x > f32(atlas.width) {
		atlas.offset.x = 0
		atlas.offset.y += atlas.row_height + 1
		atlas.row_height = 0
	}

	if atlas.offset.y + size.y > f32(atlas.height) {
		atlas.full = true
		reset_atlas(atlas)
	}

	box = {atlas.offset, atlas.offset + size}

	atlas.offset.x += size.x + 1
	atlas.row_height = max(atlas.row_height, size.y)

	return
}