package onyx

import "base:runtime"
import "core:fmt"
import "core:os"

import img "core:image"
import png "core:image/png"
import "vendor:wgpu"

Texture :: struct {
	internal:      wgpu.Texture,
	width, height: int,
}

upload_image :: proc(image: img.Image) -> (index: int, ok: bool) {
	for i in 0 ..< len(core.user_images) {
		if core.user_images[i] == nil {
			index = i
			ok = true
			core.user_images[i] = add_image_to_atlas(image)
			break
		}
	}
	return
}

drop_image :: proc(index: int) {
	core.user_images[index] = nil
}

draw_texture :: proc(
	texture: wgpu.Texture,
	box: Box,
	tint: Color,
	sampler_descriptor: Maybe(wgpu.SamplerDescriptor) = nil,
) {
	set_texture(texture)
	if sampler_descriptor != nil {
		set_sampler_descriptor(sampler_descriptor.?)
	}

	paint := add_paint({kind = .User_Texture_Sample})
	shape := add_shape_box(box, {})

	a := add_vertex({pos = box.lo, col = tint, shape = shape, paint = paint})
	b := add_vertex({pos = {box.lo.x, box.hi.y}, col = tint, uv = {0, 1}, shape = shape, paint = paint})
	c := add_vertex({pos = box.hi, col = tint, uv = 1, shape = shape, paint = paint})
	d := add_vertex({pos = {box.hi.x, box.lo.y}, col = tint, uv = {1, 0}, shape = shape, paint = paint})
	add_indices(a, b, c, a, c, d)
}

draw_texture_portion :: proc(
	texture: wgpu.Texture,
	source, target: Box,
	tint: Color,
	sampler_descriptor: Maybe(wgpu.SamplerDescriptor) = nil,
) {
	set_texture(texture)
	if sampler_descriptor != nil {
		set_sampler_descriptor(sampler_descriptor.?)
	}

	width := wgpu.TextureGetWidth(texture)
	height := wgpu.TextureGetHeight(texture)

	paint := add_paint({kind = .User_Texture_Sample})
	size: [2]f32 = {f32(width), f32(height)}
	shape := add_shape_box(target, {})

	a := add_vertex({pos = target.lo, uv = source.lo / size, col = tint, shape = shape, paint = paint})
	b := add_vertex(
		{
			pos = {target.lo.x, target.hi.y},
			col = tint,
			uv = [2]f32{source.lo.x, source.hi.y} / size,
			shape = shape, paint = paint,
		},
	)
	c := add_vertex({pos = target.hi, col = tint, uv = source.hi / size, shape = shape, paint = paint})
	d := add_vertex(
		{
			pos = {target.hi.x, target.lo.y},
			col = tint,
			uv = [2]f32{source.hi.x, source.lo.y} / size,
			shape = shape, paint = paint,
		},
	)

	add_indices(a, b, c, a, c, d)
}

create_texture_from_image :: proc(
	gfx: ^Graphics,
	image: ^img.Image,
) -> (
	texture: wgpu.Texture,
	ok: bool,
) {
	texture = wgpu.DeviceCreateTexture(
		gfx.device,
		&{
			usage = {.CopySrc, .CopyDst, .TextureBinding},
			dimension = ._2D,
			format = .RGBA8Unorm,
			size = {width = u32(image.width), height = u32(image.height), depthOrArrayLayers = 1},
			mipLevelCount = 1,
			sampleCount = 1,
		},
	)
	wgpu.QueueWriteTexture(
		gfx.queue,
		&{texture = texture},
		raw_data(image.pixels.buf),
		len(image.pixels.buf),
		&{bytesPerRow = u32(image.width * image.channels), rowsPerImage = u32(image.height)},
		&{width = u32(image.width), height = u32(image.height), depthOrArrayLayers = 1},
	)
	wgpu.QueueSubmit(gfx.queue, {})
	ok = true
	return
}
