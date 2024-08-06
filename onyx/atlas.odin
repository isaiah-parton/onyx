package onyx

import "core:slice"
import "core:fmt"
import "core:math"
import "core:math/linalg"

import sg "extra:sokol-odin/sokol/gfx"

Atlas :: struct {
	width,
	height: int,
	image: sg.Image,
	data: []u8,
	offset: [2]f32,
	row_height: f32,

	full,
	was_changed: bool,
}

init_atlas :: proc(atlas: ^Atlas, width, height: int) {
	atlas.width, atlas.height = width, height
	atlas.data = make([]u8, width * height)
	atlas.data[0] = 255
	atlas.offset = {1, 1}
	atlas.image = sg.make_image(sg.Image_Desc{
		width = i32(width),
		height = i32(height),
		usage = .DYNAMIC,
		pixel_format = .R8,
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

load_texture_from_image :: proc(image: Image) -> Texture {
	box := get_next_atlas_box(&core.atlas, {f32(image.width), f32(image.height)})
	for y in 0..<int(box.hi.y - box.lo.y) {
		copy(core.atlas.data[(int(box.lo.y) + y) * core.atlas.width + int(box.lo.x):], image.data[y * image.width:][:image.width])
	}
	core.atlas.was_changed = true
	return Texture{
		source = box,
	}
}

reset_atlas :: proc(atlas: ^Atlas) -> bool {
	width, height := atlas.width, atlas.height
	destroy_atlas(atlas)
	init_atlas(atlas, width, height)
	
	return true
}

get_next_atlas_box :: proc(atlas: ^Atlas, size: [2]f32) -> (box: Box) {

	if atlas.offset.x + size.x > f32(atlas.width) {
		atlas.offset.x = 0
		atlas.offset.y += atlas.row_height + 1
		atlas.row_height = 0
	}

	if atlas.offset.y + size.y > f32(atlas.height) {
		reset_atlas(atlas)
	}

	box = {atlas.offset, atlas.offset + size}

	atlas.offset.x += size.x + 1
	atlas.row_height = max(atlas.row_height, size.y)

	return
}