package onyx

import "core:os"
import "base:runtime"

// A transparent image struct
Image :: struct {
	data: []u8,
	width,
	height,
	channels: int,
}

// The internal image
Texture :: struct {
	source: Box,
}

load_texture_from_file :: proc(path: string) -> (index: int, ok: bool) {

	return
}

load_texture_from_memory :: proc(data: rawptr, width, height, channels: int) -> Maybe(Texture) {
	if data == nil {
		return nil
	}
	for i in 0..<MAX_TEXTURES {
		if core.textures[i] == nil {
			core.textures[i] = load_texture_from_image(Image{
				data = transmute([]u8)runtime.Raw_Slice{
					data = data,
					len = width * height * channels,
				},
				width = width,
				height = height,
				channels = channels,
			})
			return core.textures[i]
		}
	}
	return nil
}

load_image :: proc {
	load_texture_from_file,
	load_texture_from_memory,
}

delete_image :: proc(image: ^Image) {
	delete(image.data)
}

// Release a user image to be deleted
drop_texture :: proc(index: int) {
	core.textures[index] = nil
}

// Draws a user image inside `box`
draw_texture_index :: proc(index: int, box: Box, tint: Color) {
	draw_texture(core.textures[index].?, box, tint)
}

draw_texture :: proc(tex: Texture, box: Box, tint: Color) {

	vertex_uv(tex.source.lo)
	tl := add_vertex(box.lo)
	vertex_uv({tex.source.lo.x, tex.source.hi.y})
	bl := add_vertex({box.lo.x, box.hi.y})
	vertex_uv(tex.source.hi)
	br := add_vertex(box.hi)
	vertex_uv({tex.source.hi.x, tex.source.lo.y})
	tr := add_vertex({box.hi.x, box.lo.y})

	add_indices(tl, bl, br, tl, br, tr)
}

draw_texture_portion :: proc(index: int, source, target: Box, tint: Color) {
	tex := &core.textures[index].?

	vertex_uv(tex.source.lo + source.lo)
	tl := add_vertex(target.lo)
	vertex_uv(tex.source.lo + {source.lo.x, source.hi.y})
	bl := add_vertex({target.lo.x, target.hi.y})
	vertex_uv(tex.source.lo + source.hi)
	br := add_vertex(target.hi)
	vertex_uv(tex.source.lo + {source.hi.x, source.lo.y})
	tr := add_vertex({target.hi.x, target.lo.y})

	add_indices(tl, bl, br, tl, br, tr)
}