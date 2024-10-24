package onyx

import "core:bytes"
import "core:fmt"
import img "core:image"
import "core:math"
import "core:math/linalg"
import "core:mem"
import "core:slice"
import "core:sync"

import "vendor:wgpu"

Atlas :: struct {
	image:          img.Image,
	texture:        Texture,
	width, height:  int,
	offset:         [2]f32,
	row_height:     f32,
	full, modified: bool,
	modified_box:   Box,
	mutex: 					sync.Mutex,
}

init_atlas :: proc(atlas: ^Atlas, gfx: ^Graphics, width, height: int) {
	atlas.width, atlas.height = width, height

	resize(&atlas.image.pixels.buf, width * height * 4)

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
}

destroy_atlas :: proc(atlas: ^Atlas) {
	bytes.buffer_destroy(&atlas.image.pixels)
	wgpu.TextureDestroy(atlas.texture.internal)
}

update_atlas :: proc(atlas: ^Atlas, gfx: ^Graphics) {
	if atlas.modified_box.hi.x <= atlas.modified_box.lo.x ||
	   atlas.modified_box.hi.y <= atlas.modified_box.lo.y {
		return
	}

	pixel_offset := (int(atlas.modified_box.lo.x) + int(atlas.modified_box.lo.y) * atlas.width) * 4
	pixels := atlas.image.pixels.buf[pixel_offset:]

	wgpu.QueueWriteTexture(
		gfx.queue,
		&{
			texture = atlas.texture.internal,
			origin = {x = u32(atlas.modified_box.lo.x), y = u32(atlas.modified_box.lo.y)},
		},
		raw_data(pixels),
		len(pixels),
		&{bytesPerRow = u32(atlas.width) * 4, rowsPerImage = u32(atlas.height)},
		&{
			width = u32(box_width(atlas.modified_box)),
			height = u32(box_height(atlas.modified_box)),
			depthOrArrayLayers = 1,
		},
	)
	wgpu.QueueSubmit(gfx.queue, {})
	atlas.modified_box = {math.F32_MAX, 0}
}

add_glyph_to_atlas :: proc(data: [^]u8, width, height: int, atlas: ^Atlas, gfx: ^Graphics) -> Box {
	box := get_next_atlas_box(atlas, gfx, {f32(width + 1), f32(height + 1)})

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
	atlas.modified_box = update_bounding(atlas.modified_box, box)
	return box
}

// Copy an image to the atlas
// Mutex protected
add_image_to_atlas :: proc(image: img.Image) -> Box {
	atlas := &core.atlas
	gfx := &core.gfx

	sync.mutex_lock(&atlas.mutex)
	defer sync.mutex_unlock(&atlas.mutex)

	box := get_next_atlas_box(atlas, gfx, {f32(image.width), f32(image.height)})
	pixel_size := 4
	for y in 0 ..< image.height {
		target_row_offset := (y + int(box.lo.y)) * atlas.width * pixel_size
		source_row_offset := y * image.width * pixel_size
		for x in 0 ..< image.width {
			target_offset := target_row_offset + (x + int(box.lo.x)) * pixel_size
			source_offset := source_row_offset + x * pixel_size
			atlas.image.pixels.buf[target_offset] = image.pixels.buf[source_offset]
			atlas.image.pixels.buf[target_offset + 1] = image.pixels.buf[source_offset + 1]
			atlas.image.pixels.buf[target_offset + 2] = image.pixels.buf[source_offset + 2]
			atlas.image.pixels.buf[target_offset + 3] = image.pixels.buf[source_offset + 3]
		}
	}
	atlas.modified = true
	atlas.modified_box = update_bounding(atlas.modified_box, box)
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
