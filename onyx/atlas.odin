package onyx

import "core:bytes"
import "core:fmt"
import img "core:image"
import "core:math"
import "core:math/linalg"
import "core:mem"
import "core:slice"

import sg "extra:sokol-odin/sokol/gfx"

Atlas :: struct {
	image:          img.Image,
	texture:        Texture,
	offset:         [2]f32,
	row_height:     f32,
	full, modified: bool,
}

init_atlas :: proc(atlas: ^Atlas, width, height: int) {
	pixels := make([]u8, width * height * 4)
	defer delete(pixels)

	pixels[0] = 255
	pixels[1] = 255
	pixels[2] = 255
	pixels[3] = 255
	atlas.offset = {1, 1}

	image_desc := sg.Image_Desc {
		width = i32(width),
		height = i32(height),
		usage = .DYNAMIC,
		pixel_format = .RGBA8,
	}

		image_desc.data = {subimage = {0 = {0 = {ptr = raw_data(pixels), size = u64(len(pixels))}}}}

	atlas.texture = {
		image  = sg.make_image(image_desc),
		width  = width,
		height = height,
	}
	bytes.buffer_init(&atlas.image.pixels, pixels)
}

destroy_atlas :: proc(atlas: ^Atlas) {
	bytes.buffer_destroy(&atlas.image.pixels)
	sg.destroy_image(atlas.texture)
}

update_atlas :: proc(atlas: ^Atlas) {
	sg.update_image(
		atlas.texture,
		{
			subimage = {
				0 = {
					0 = {
						ptr = raw_data(atlas.image.pixels.buf),
						size = u64(len(atlas.image.pixels.buf)),
					},
				},
			},
		},
	)
}

add_glyph_to_atlas :: proc(data: [^]u8, width, height: int, atlas: ^Atlas) -> Box {
	box := get_next_atlas_box(atlas, {f32(width), f32(height)})

	pixel_size: int = 4

	for y in 0 ..< height {
		target_row_offset := (y + int(box.lo.y)) * atlas.texture.width * pixel_size
		source_row_offset := y * width
		for x in 0 ..< width {
			target_offset := target_row_offset + (x + int(box.lo.x)) * pixel_size
			atlas.image.pixels.buf[target_offset] = 255
			atlas.image.pixels.buf[target_offset + 1] = 255
			atlas.image.pixels.buf[target_offset + 2] = 255
			atlas.image.pixels.buf[target_offset + 3] = data[source_row_offset + x]
		}
	}
	atlas.modified = true
	return box
}

add_image_to_atlas :: proc(image: img.Image, atlas: ^Atlas) -> Box {
	box := get_next_atlas_box(atlas, {f32(image.width), f32(image.height)})
	pixel_size := 4
	for y in 0 ..< image.height {
		target_row_offset := (y + int(box.lo.y)) * atlas.texture.width * pixel_size
		source_row_offset := y * image.width
		for x in 0 ..< image.width {
			target_offset := target_row_offset + (x + int(box.lo.x)) * pixel_size
			atlas.image.pixels.buf[target_offset] = image.pixels.buf[source_row_offset + x]
			atlas.image.pixels.buf[target_offset + 1] = image.pixels.buf[source_row_offset + x + 1]
			atlas.image.pixels.buf[target_offset + 2] = image.pixels.buf[source_row_offset + x + 2]
			atlas.image.pixels.buf[target_offset + 3] = image.pixels.buf[source_row_offset + x + 3]
		}
	}
	atlas.modified = true
	return box
}

reset_atlas :: proc(atlas: ^Atlas) -> bool {
	width, height := atlas.texture.width, atlas.texture.height
	destroy_atlas(atlas)
	init_atlas(atlas, width, height)
	atlas.full = false

	return true
}

get_next_atlas_box :: proc(atlas: ^Atlas, size: [2]f32) -> (box: Box) {

	if atlas.offset.x + size.x > f32(atlas.texture.width) {
		atlas.offset.x = 0
		atlas.offset.y += atlas.row_height + 1
		atlas.row_height = 0
	}

	if atlas.offset.y + size.y > f32(atlas.texture.height) {
		atlas.full = true
		reset_atlas(atlas)
	}

	box = {atlas.offset, atlas.offset + size}

	atlas.offset.x += size.x + 1
	atlas.row_height = max(atlas.row_height, size.y)

	return
}
