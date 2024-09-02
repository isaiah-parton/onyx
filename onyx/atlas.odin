package onyx

import "core:bytes"
import "core:fmt"
import img "core:image"
import "core:math"
import "core:math/linalg"
import "core:mem"
import "core:slice"

import "vendor:wgpu"

Atlas :: struct {
	image:          img.Image,
	texture:        Texture,
	width, height:  int,
	offset:         [2]f32,
	row_height:     f32,
	full, modified: bool,
}

init_atlas :: proc(atlas: ^Atlas, gfx: ^Graphics, width, height: int) {
	atlas.width, atlas.height = width, height
	pixels := make([]u8, width * height * 4)
	defer delete(pixels)
	assert(len(pixels) > 0)
	pixels[0] = 255
	pixels[1] = 255
	pixels[2] = 255
	pixels[3] = 255
	atlas.offset = {1, 1}

	atlas.texture = {
		width    = width,
		height   = height,
		internal = wgpu.DeviceCreateTexture(
			gfx.device,
			&{
				usage = {.CopySrc, .CopyDst, .TextureBinding},
				dimension = ._2D,
				size = {u32(width), u32(height), 1},
				format = .RGBA8Unorm,
				mipLevelCount = 1,
				sampleCount = 1,
			},
		),
	}
	bytes.buffer_init(&atlas.image.pixels, pixels)

}

destroy_atlas :: proc(atlas: ^Atlas) {
	bytes.buffer_destroy(&atlas.image.pixels)
	wgpu.TextureDestroy(atlas.texture.internal)
}

update_atlas :: proc(atlas: ^Atlas, gfx: ^Graphics) {
	wgpu.QueueWriteTexture(
		gfx.queue,
		&{texture = atlas.texture.internal},
		raw_data(atlas.image.pixels.buf),
		len(atlas.image.pixels.buf),
		&{bytesPerRow = u32(atlas.width) * 4, rowsPerImage = u32(atlas.height)},
		&{width = u32(atlas.width), height = u32(atlas.height), depthOrArrayLayers = 1},
	)
}

add_glyph_to_atlas :: proc(data: [^]u8, width, height: int, atlas: ^Atlas, gfx: ^Graphics) -> Box {
	box := get_next_atlas_box(atlas, gfx, {f32(width), f32(height)})

	pixel_size: int = 4

	for y in 0 ..< height {
		target_row_offset := (y + int(box.lo.y)) * atlas.width * pixel_size
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

add_image_to_atlas :: proc(image: img.Image, atlas: ^Atlas, gfx: ^Graphics) -> Box {
	box := get_next_atlas_box(atlas, gfx, {f32(image.width), f32(image.height)})
	pixel_size := 4
	for y in 0 ..< image.height {
		target_row_offset := (y + int(box.lo.y)) * atlas.width * pixel_size
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

reset_atlas :: proc(atlas: ^Atlas, gfx: ^Graphics) -> bool {
	width, height := atlas.width, atlas.height
	destroy_atlas(atlas)
	init_atlas(atlas, gfx, width, height)
	atlas.full = false

	return true
}

get_next_atlas_box :: proc(atlas: ^Atlas, gfx: ^Graphics, size: [2]f32) -> (box: Box) {

	if atlas.offset.x + size.x > f32(atlas.width) {
		atlas.offset.x = 0
		atlas.offset.y += atlas.row_height + 1
		atlas.row_height = 0
	}

	if atlas.offset.y + size.y > f32(atlas.height) {
		atlas.full = true
		reset_atlas(atlas, gfx)
	}

	box = {atlas.offset, atlas.offset + size}

	atlas.offset.x += size.x + 1
	atlas.row_height = max(atlas.row_height, size.y)

	return
}
