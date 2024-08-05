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
	cursor: [2]f32,
	row_height: f32,

	full,
	was_changed: bool,
	times_accessed: int,
}

init_atlas :: proc(atlas: ^Atlas, width, height: int) {
	atlas.width, atlas.height = width, height
	atlas.data = make([]u8, width * height)
	atlas.data[0] = 255
	atlas.cursor = {1, 1}
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
	for &font in atlas.fonts {
		if font, ok := &font.?; ok {
			destroy_font(font)
		}
	}
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

/*
	Get a pre-rasterized ring from the atlas or create one
*/
/*
get_atlas_ring :: proc(atlas: ^Atlas, inner, outer: f32) -> (src: Box, ok: bool) {
	_inner := int(inner)
	_outer := int(outer)
	if _inner < 0 || _inner >= MAX_RING_RADIUS || _outer < 0 || _outer >= MAX_RING_RADIUS {
		return {}, false
	}
	ring := &painter.rings[_inner][_outer]
	if ring^ == nil {
		ring^, _ = add_atlas_ring(painter, inner, outer)
	}
	return ring^.?
}
*/

reset_atlas :: proc(atlas: ^Atlas) -> bool {
	width, height := atlas.width, atlas.height
	destroy_atlas(atlas)
	init_atlas(atlas, width, height)
	
	return true
}

add_atlas_image :: proc(atlas: ^Atlas, content: Image) -> (src: [2][2]f32, ok: bool) {
	box := get_atlas_box(atlas, {f32(content.width), f32(content.height)})
	for y in 0..<int(box.hi.y - box.lo.y) {
		copy(atlas.data[(int(box.lo.y) + y) * atlas.width + int(box.lo.x):], content.data[y * content.width:][:content.width])
	}
	atlas.was_changed = true
	return box, true
}

get_atlas_box :: proc(atlas: ^Atlas, size: [2]f32) -> (box: [2][2]f32) {
	if atlas.cursor.x + size.x > f32(atlas.width) {
		atlas.cursor.x = 0
		atlas.cursor.y += atlas.row_height + 1
		atlas.row_height = 0
	}
	if atlas.cursor.y + size.y > f32(atlas.height) {
		reset_atlas(atlas)
	}
	box = {atlas.cursor, atlas.cursor + size}
	atlas.cursor.x += size.x + 1
	atlas.row_height = max(atlas.row_height, size.y)
	return
}
/*
	Generate a anti-aliased ring and place in on the atlas
		Returns the location if it was successful
*/
add_atlas_ring :: proc(atlas: ^Atlas, inner, outer: f32) -> (src: [2][2]f32, ok: bool) {
	if inner >= outer {
		return
	}
	box := get_atlas_box(atlas, outer * 2)
	center: [2]f32 = box_center(box) - 0.5
	outer := outer - 0.5
	inner := inner - 0.5
	for y in int(box.lo.y)..<int(box.hi.y) {
		for x in int(box.lo.x)..<int(box.hi.x) {
			point: [2]f32 = {f32(x), f32(y)}
			diff := point - center
			dist := math.sqrt((diff.x * diff.x) + (diff.y * diff.y))
			if dist < inner || dist > outer + 1 {
				continue
			}
			alpha := min(1, dist - inner) - max(0, dist - outer)
			i := (x + y * atlas.width)
			atlas.data[i] = u8(255.0 * alpha)
		}
	}
	atlas.was_changed = true
	return box, ok
}