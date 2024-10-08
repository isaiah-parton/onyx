package onyx

import "base:runtime"
import "core:fmt"
import "core:os"

import img "core:image"
import png "core:image/png"
import "vendor:wgpu"

Image :: struct {
	using image: img.Image,
	atlas_src:   Maybe(Box),
}

Texture :: struct {
	internal:      wgpu.Texture,
	width, height: int,
}

upload_image :: proc(image: img.Image) -> (index: int, ok: bool) {
	for i in 0 ..< len(core.user_images) {
		if core.user_images[i] == nil {
			index = i
			ok = true
			core.user_images[i] = Image{}
			break
		}
	}
	return
}

drop_image :: proc(index: int) {
	core.user_images[index] = nil
}

destroy_image :: proc(image: ^Image) {
	img.destroy(image)
}

draw_texture :: proc(texture: wgpu.Texture, box: Box, tint: Color) {
	// last_texture := get_current_texture()
	set_texture(texture)

	set_vertex_color(tint)

	set_vertex_uv(0)
	tl := add_vertex(box.lo)
	set_vertex_uv({0, 1})
	bl := add_vertex({box.lo.x, box.hi.y})
	set_vertex_uv(1)
	br := add_vertex(box.hi)
	set_vertex_uv({1, 0})
	tr := add_vertex({box.hi.x, box.lo.y})

	add_indices(tl, br, bl, tl, tr, br)

	// set_texture(last_texture)
}

draw_texture_portion :: proc(texture: Texture, source, target: Box, tint: Color) {
	last_texture := get_current_texture()
	set_texture(texture.internal)
	set_vertex_color(tint)

	size: [2]f32 = {f32(texture.width), f32(texture.height)}

	set_vertex_shape(add_shape(Shape{kind = .Normal}))
	set_vertex_uv(source.lo / size)
	tl := add_vertex(target.lo)
	set_vertex_uv({source.lo.x, source.hi.y} / size)
	bl := add_vertex({target.lo.x, target.hi.y})
	set_vertex_uv(source.hi / size)
	br := add_vertex(target.hi)
	set_vertex_uv({source.hi.x, source.lo.y} / size)
	tr := add_vertex({target.hi.x, target.lo.y})

	add_indices(tl, br, bl, tl, tr, br)
	set_vertex_shape(0)
	set_texture(last_texture)
}

draw_glyph :: proc(source, target: Box, tint: Color) {
	size: [2]f32 = {f32(core.font_atlas.width), f32(core.font_atlas.height)}
	set_vertex_shape(add_shape(Shape{kind = .Normal}))
	set_vertex_uv(source.lo / size)
	set_vertex_color(tint)

	tl := add_vertex(target.lo)
	set_vertex_uv({source.lo.x, source.hi.y} / size)
	bl := add_vertex({target.lo.x, target.hi.y})
	set_vertex_uv(source.hi / size)
	br := add_vertex(target.hi)
	set_vertex_uv({source.hi.x, source.lo.y} / size)
	tr := add_vertex({target.hi.x, target.lo.y})

	add_indices(tl, br, bl, tl, tr, br)

	set_vertex_shape(0)
}

set_texture :: proc(texture: wgpu.Texture) {
	core.current_texture = texture
	if core.current_draw_call == nil do return
	if core.current_draw_call.user_texture == core.current_texture do return
	if core.current_draw_call.user_texture != nil {
		append_draw_call(current_layer().?.index)
	}
	core.current_draw_call.user_texture = texture
}

get_current_texture :: proc() -> wgpu.Texture {
	return core.current_texture
}

create_texture_from_image :: proc(gfx: ^Graphics, image: ^img.Image) -> (texture: wgpu.Texture, ok: bool) {
	texture = wgpu.DeviceCreateTexture(gfx.device, &{
		usage = {.CopySrc, .CopyDst, .TextureBinding},
		dimension = ._2D,
		format = .RGBA8Unorm,
		size = {
			width = u32(image.width),
			height = u32(image.height),
			depthOrArrayLayers = 1,
		},
		mipLevelCount = 1,
		sampleCount = 1,
	})
	wgpu.QueueWriteTexture(
		gfx.queue,
		&{
			texture = texture,
		},
		raw_data(image.pixels.buf),
		len(image.pixels.buf),
		&{bytesPerRow = u32(image.width * image.channels), rowsPerImage = u32(image.height)},
		&{
			width = u32(image.width),
			height = u32(image.height),
			depthOrArrayLayers = 1,
		},
	)
	wgpu.QueueSubmit(gfx.queue, {})
	ok = true
	return
}
