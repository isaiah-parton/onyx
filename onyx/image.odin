package onyx

import "core:fmt"
import "core:os"
import "base:runtime"

import "core:image/png"

import sg "extra:sokol-odin/sokol/gfx"

Pixel_Format :: sg.Pixel_Format

Image :: struct {
	using _image: sg.Image,

	width,
	height: int,
	pixel_format: Pixel_Format,
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

load_image_from_file :: proc(file: string) -> (image: Image, err: png.Error) {
	_image := png.load_from_file(file) or_return
	image = Image{
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
			pixel_format = .RGBA8,
		}),
		width = _image.width,
		height = _image.height,
		pixel_format = .RGBA8,
	}
	return
}