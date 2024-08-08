package onyx

import "core:fmt"
import "core:os"
import "base:runtime"

import "core:image"
import "core:image/png"

import sg "extra:sokol-odin/sokol/gfx"

Pixel_Format :: sg.Pixel_Format

Image :: struct {
	using _image: sg.Image,

	channels,
	depth,
	width,
	height: int,
}

destroy_image :: proc(image: ^Image) {
	sg.destroy_image(image)
}

draw_image :: proc(image: Image, box: Box, tint: Color) {
	prev_image := get_current_image()
	set_image(image)

	vertex_col(tint)

	vertex_uv(0)
	tl := add_vertex(box.lo)
	vertex_uv({0, 1})
	bl := add_vertex({box.lo.x, box.hi.y})
	vertex_uv(1)
	br := add_vertex(box.hi)
	vertex_uv({1, 0})
	tr := add_vertex({box.hi.x, box.lo.y})

	add_indices(tl, br, bl, tl, tr, br)

	set_image(prev_image)
}

draw_image_portion :: proc(image: Image, source, target: Box, tint: Color) {
	prev_image := get_current_image()
	set_image(image)

	vertex_col(tint)

	size: [2]f32 = {
		f32(image.width),
		f32(image.height),
	}

	vertex_uv(source.lo / size)
	tl := add_vertex(target.lo)
	vertex_uv({source.lo.x, source.hi.y} / size)
	bl := add_vertex({target.lo.x, target.hi.y})
	vertex_uv(source.hi / size)
	br := add_vertex(target.hi)
	vertex_uv({source.hi.x, source.lo.y} / size)
	tr := add_vertex({target.hi.x, target.lo.y})

	add_indices(tl, br, bl, tl, tr, br)

	set_image(prev_image)
}

set_image :: proc(image: sg.Image) {
	if core.current_draw_call.bindings.fs.images[0] == image {
		return
	}
	for i in 0..<core.draw_call_count {
		if core.draw_calls[i].bindings.fs.images[0] == image {
			core.current_draw_call = &core.draw_calls[i]
			return
		}
	}
	push_draw_call()
	core.current_draw_call.bindings.fs.images[0] = image
}

get_current_image :: proc() -> sg.Image {
	return core.current_draw_call.bindings.fs.images[0]
}

get_pixel_format :: proc(channels, depth: int) -> sg.Pixel_Format {
	switch channels {
		case 1:
		switch depth {
			case 8: return .R8
			case 16: return .R16
			case 32: return .R32F
		}
		case 2:
		switch depth {
			case 8: return .RG8
			case 16: return .RG16
			case 32: return .RG32F
		}
		case 4:
		switch depth {
			case 8: return .RGBA8
			case 16: return .RGBA16
			case 32: return .RGBA32F
		}
	}
	return .NONE
}

load_image_from_file :: proc(file: string) -> (result: Image, err: png.Error) {
	_image := png.load_from_file(file) or_return
	image.alpha_add_if_missing(_image)
	pixel_format := get_pixel_format(_image.channels, _image.depth)
	result = Image{
		_image = sg.make_image(sg.Image_Desc{
			data = {
				subimage = {
					0 = {
						0 = {
							ptr = raw_data(_image.pixels.buf),
							size = u64(len(_image.pixels.buf)),
						},
					},
				},
			},
			width = i32(_image.width),
			height = i32(_image.height),
			pixel_format = pixel_format,
		}),
		width = _image.width,
		height = _image.height,
		channels = _image.channels,
		depth = _image.depth,
	}
	
	return
}
