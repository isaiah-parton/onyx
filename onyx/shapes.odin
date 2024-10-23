package onyx

import "core:fmt"
import "core:math"
import "core:math/ease"
import "core:math/linalg"
import "core:time"

ANGLE_TOLERANCE :: 0.01

add_shape_box :: proc(box: Box, corners: [4]f32) -> u32 {
	return add_shape(Shape{kind = .Box, corners = corners, cv0 = box.lo, cv1 = box.hi})
}

add_shape_circle :: proc(center: [2]f32, radius: f32) -> u32 {
	return add_shape(Shape{kind = .Circle, cv0 = center, radius = radius})
}

add_shape :: proc(shape: Shape) -> u32 {
	index := u32(len(core.gfx.shapes.data))
	shape := shape
	// Assign current shape defaults
	shape.paint = core.draw_state.paint
	shape.scissor = core.draw_state.scissor
	// Try use the current matrix
	if core.current_matrix != nil && core.current_matrix^ != core.last_matrix {
		core.matrix_index = u32(len(core.gfx.xforms.data))
		append(&core.gfx.xforms.data, core.current_matrix^)
		core.last_matrix = core.current_matrix^
	}
	shape.xform = core.matrix_index
	// Append the shape
	append(&core.gfx.shapes.data, shape)
	return index
}

get_shape_bounding_box :: proc(shape: Shape) -> Box {
	box: Box = {math.F32_MAX, 0}
	switch shape.kind {
	case .Normal:
	case .Box:
		box.lo = shape.cv0 - 1
		box.hi = shape.cv1 + 1
	case .Circle:
		box.lo = shape.cv0 - shape.radius
		box.hi = shape.cv0 + shape.radius
	case .Path:
		for i in 0 ..< shape.count * 3 {
			j := shape.start + i
			box.lo = linalg.min(box.lo, core.gfx.cvs.data[j])
			box.hi = linalg.max(box.hi, core.gfx.cvs.data[j])
		}
	case .Polygon:
		for i in 0 ..< shape.count {
			j := shape.start + i
			box.lo = linalg.min(box.lo, core.gfx.cvs.data[j])
			box.hi = linalg.max(box.hi, core.gfx.cvs.data[j])
		}
		box.lo -= 1
		box.hi += 1
	case .Bezier:
		box.lo = linalg.min(shape.cv0, shape.cv1, shape.cv2) - shape.width * 2
		box.hi = linalg.max(shape.cv0, shape.cv1, shape.cv2) + shape.width * 2
	case .BlurredBox:
		box.lo = shape.cv0 - shape.cv1 * 3
		box.hi = shape.cv0 + shape.cv1 * 3
	case .Arc, .Pie:
		box.lo = shape.cv0 - shape.radius - shape.width
		box.hi = shape.cv0 + shape.radius + shape.width
	}

	if shape.stroke {
		box.lo -= shape.width / 2
		box.hi += shape.width / 2
	}
	return box
}

apply_scissor_box :: proc(target, source: ^Box, clip: Box) {
	left := clip.lo.x - target.lo.x
	source_factor := box_size(source^) / box_size(target^)
	if left > 0 {
		target.lo.x += left
		source.lo.x += left * source_factor.x
	}
	top := clip.lo.y - target.lo.y
	if top > 0 {
		target.lo.y += top
		source.lo.y += top * source_factor.y
	}
	right := target.hi.x - clip.hi.x
	if right > 0 {
		target.hi.x -= right
		source.hi.x -= right * source_factor.x
	}
	bottom := target.hi.y - clip.hi.y
	if bottom > 0 {
		target.hi.y -= bottom
		source.hi.y -= bottom * source_factor.y
	}
}

render_shape :: proc(shape_index: u32, color: Color) {
	shape := core.gfx.shapes.data[shape_index]
	// Get full bounding box
	box := get_shape_bounding_box(shape)
	// Apply scissor clipping
	// Shadows are not clipped like other shapes since they are currently only drawn below new layers
	// This is subject to change.
	if shape.kind != .BlurredBox {
		if scissor, ok := current_scissor().?; ok {
			box.lo = linalg.max(box.lo, scissor.box.lo)
			box.hi = linalg.min(box.hi, scissor.box.hi)
		}
	}
	// Discard fully clipped shapes
	if box.lo.x >= box.hi.x || box.lo.y >= box.hi.y do return
	// Add vertices
	a := add_vertex(Vertex{pos = box.lo, col = color, uv = 0, shape = shape_index})
	b := add_vertex(
		Vertex{pos = {box.lo.x, box.hi.y}, col = color, uv = {0, 1}, shape = shape_index},
	)
	c := add_vertex(Vertex{pos = box.hi, col = color, uv = 1, shape = shape_index})
	d := add_vertex(
		Vertex{pos = {box.hi.x, box.lo.y}, col = color, uv = {1, 0}, shape = shape_index},
	)
	add_indices(a, b, c, a, c, d)
}

render_shape_uv :: proc(shape_index: u32, source: Box, color: Color) {
	shape := core.gfx.shapes.data[shape_index]
	box := get_shape_bounding_box(shape)
	source := source
	// Apply scissor clipping
	// Shadows are not clipped like other shapes since they are currently only drawn below new layers
	// This is subject to change.
	if scissor, ok := current_scissor().?; ok {
		apply_scissor_box(&box, &source, scissor.box)
	}
	// Discard fully clipped shapes
	if box.lo.x >= box.hi.x || box.lo.y >= box.hi.y do return
	// Get texture size
	size := [2]f32{f32(core.atlas.width), f32(core.atlas.height)}
	// Add vertices
	a := add_vertex(Vertex{pos = box.lo, col = color, uv = source.lo / size, shape = shape_index})
	b := add_vertex(
		Vertex {
			pos = [2]f32{box.lo.x, box.hi.y},
			col = color,
			uv = [2]f32{source.lo.x, source.hi.y} / size,
			shape = shape_index,
		},
	)
	c := add_vertex(Vertex{pos = box.hi, col = color, uv = source.hi / size, shape = shape_index})
	d := add_vertex(
		Vertex {
			pos = [2]f32{box.hi.x, box.lo.y},
			col = color,
			uv = [2]f32{source.hi.x, source.lo.y} / size,
			shape = shape_index,
		},
	)
	add_indices(a, b, c, a, c, d)
}

clear_path :: proc(path: ^Path) {
	path.count = 0
}

get_path :: proc() -> ^Path {
	return &core.path_stack.items[core.path_stack.height - 1]
}

begin_path :: proc() {
	push_stack(&core.path_stack, Path{})
}

end_path :: proc() {
	pop_stack(&core.path_stack)
}

close_path :: proc() {
	get_path().closed = true
}

point :: proc(point: [2]f32) {
	path := get_path()
	if path.count >= MAX_PATH_POINTS {
		return
	}
	path.points[path.count] = point
	path.count += 1
}

bezier :: proc(p0, p1, p2, p3: [2]f32, segments: int) {
	step: f32 = 1.0 / f32(segments)
	for t: f32 = step; t <= 1; t += step {
		times: matrix[1, 4]f32 = {1, t, t * t, t * t * t}
		weights: matrix[4, 4]f32 = {1, 0, 0, 0, -3, 3, 0, 0, 3, -6, 3, 0, -1, 3, -3, 1}
		point(
			{
				(times * weights * (matrix[4, 1]f32){p0.x, p1.x, p2.x, p3.x})[0][0],
				(times * weights * (matrix[4, 1]f32){p0.y, p1.y, p2.y, p3.y})[0][0],
			},
		)
	}
}

arc :: proc(center: [2]f32, radius, from, to: f32) {
	da := to - from
	nsteps := int(abs(da) / ANGLE_TOLERANCE)
	for n in 1 ..< nsteps {
		a := from + da * f32(n) / f32(nsteps)
		point(center + {math.cos(a), math.sin(a)} * radius)
	}
}

fill_path :: proc(color: Color) {

	// path := get_path()
	// if path.count < 3 {
	// 	return
	// }
	// index := add_vertex(path.points[0])
	// for i in 1 ..< path.count {
	// 	add_vertex(path.points[i])
	// 	if i < path.count - 1 {
	// 		add_indices(index, index + u32(i), index + u32(i) + 1)
	// 	}
	// }
}

stroke_path :: proc(thickness: f32, color: Color, justify: Stroke_Justify = .Center) {
	path := get_path()
	if path.count < 2 {
		return
	}
	left, right: f32
	switch justify {
	case .Center:
		left = thickness / 2
		right = left
	case .Outer:
		left = thickness
	case .Inner:
		right = thickness
	}
	v0, v1: [2]f32
	for i in 0 ..< path.count {
		a := i - 1
		b := i
		c := i + 1
		d := i + 2
		if a < 0 {
			if path.closed {
				a = path.count - 1
			} else {
				a = 0
			}
		}
		if path.closed {
			c = c % path.count
			d = d % path.count
		} else {
			c = min(path.count - 1, c)
			d = min(path.count - 1, d)
		}
		p0 := path.points[a]
		p1 := path.points[b]
		p2 := path.points[c]
		p3 := path.points[d]
		if p1 == p2 {
			continue
		}
		line := linalg.normalize(p2 - p1)
		normal := linalg.normalize([2]f32{-line.y, line.x})
		tangent2 := line if p2 == p3 else linalg.normalize(linalg.normalize(p3 - p2) + line)
		miter2: [2]f32 = {-tangent2.y, tangent2.x}
		dot2 := linalg.dot(normal, miter2)
		// Start of segment
		if i == 0 {
			tangent1 := line if p0 == p1 else linalg.normalize(linalg.normalize(p1 - p0) + line)
			miter1: [2]f32 = {-tangent1.y, tangent1.x}
			dot1 := linalg.dot(normal, miter1)
			v0 = p1 - (left / dot1) * miter1
			v1 = p1 + (right / dot1) * miter1
		}
		// End of segment
		nv0 := p2 - (left / dot2) * miter2
		nv1 := p2 + (right / dot2) * miter2
		// Add a polygon for each quad
		draw_polygon_fill({v0, v1, nv1, nv0}, color)
		v0, v1 = nv0, nv1
	}
}

__join_miter :: proc(p0, p1, p2: [2]f32) -> (dot: f32, miter: [2]f32) {
	line := linalg.normalize(p2 - p1)
	normal := linalg.normalize([2]f32{-line.y, line.x})
	tangent := line if p0 == p1 else linalg.normalize(linalg.normalize(p1 - p0) + line)
	miter = {-tangent.y, tangent.x}
	dot = linalg.dot(normal, miter)
	return
}

normalize_color :: proc(color: Color) -> [4]f32 {
	return {f32(color.r) / 255.0, f32(color.g) / 255.0, f32(color.b) / 255.0, f32(color.a) / 255.0}
}

draw_glyph :: proc(source, target: Box, tint: Color) {
	source, target := source, target
	if scissor, ok := current_scissor().?; ok {
		left := scissor.box.lo.x - target.lo.x
		if left > 0 {
			target.lo.x += left
			source.lo.x += left
		}
		top := scissor.box.lo.y - target.lo.y
		if top > 0 {
			target.lo.y += top
			source.lo.y += top
		}
		right := target.hi.x - scissor.box.hi.x
		if right > 0 {
			target.hi.x -= right
			source.hi.x -= right
		}
		bottom := target.hi.y - scissor.box.hi.y
		if bottom > 0 {
			target.hi.y -= bottom
			source.hi.y -= bottom
		}
		if target.lo.x >= target.hi.x || target.lo.y >= target.hi.y do return
	}
	size: [2]f32 = {f32(core.atlas.width), f32(core.atlas.height)}
	set_paint(1)
	shape_index := add_shape(Shape{kind = .Normal})
	a := add_vertex(
		Vertex{pos = target.lo, col = tint, uv = source.lo / size, shape = shape_index},
	)
	b := add_vertex(
		Vertex {
			pos = [2]f32{target.lo.x, target.hi.y},
			col = tint,
			uv = [2]f32{source.lo.x, source.hi.y} / size,
			shape = shape_index,
		},
	)
	c := add_vertex(
		Vertex{pos = target.hi, col = tint, uv = source.hi / size, shape = shape_index},
	)
	d := add_vertex(
		Vertex {
			pos = [2]f32{target.hi.x, target.lo.y},
			col = tint,
			uv = [2]f32{source.hi.x, source.lo.y} / size,
			shape = shape_index,
		},
	)
	add_indices(a, b, c, a, c, d)
	set_paint(0)
}

draw_triangle_fill :: proc(a, b, c: [2]f32, color: Color) {
	draw_polygon_fill({a, b, c}, color)
}

// TODO: Remove
// draw_triangle_strip_fill :: proc(points: [][2]f32, color: Color) {
// 	if len(points) < 4 {
// 		return
// 	}
// 	for i in 2 ..< len(points) {
// 		if i % 2 == 0 {
// 			draw_triangle_fill(
// 				{points[i].x, points[i].y},
// 				{points[i - 2].x, points[i - 2].y},
// 				{points[i - 1].x, points[i - 1].y},
// 				color,
// 			)
// 		} else {
// 			draw_triangle_fill(
// 				{points[i].x, points[i].y},
// 				{points[i - 1].x, points[i - 1].y},
// 				{points[i - 2].x, points[i - 2].y},
// 				color,
// 			)
// 		}
// 	}
// }

draw_line :: proc(a, b: [2]f32, width: f32, color: Color) {
	delta := b - a
	length := math.sqrt(f32(delta.x * delta.x + delta.y * delta.y))
	if length > 0 && width > 0 {
		scale := width / (2 * length)
		radius: [2]f32 = {-scale * delta.y, scale * delta.x}
		draw_polygon_fill(
			{
				{a.x + radius.x, a.y + radius.y},
				{a.x - radius.x, a.y - radius.y},
				{b.x - radius.x, b.y - radius.y},
				{b.x + radius.x, b.y + radius.y},
			},
			color,
		)
	}
}

draw_quad_bezier :: proc(a, b, c: [2]f32, width: f32, color: Color) {
	shape_index := add_shape(Shape{kind = .Bezier, cv0 = a, cv1 = b, cv2 = c, width = width})
	render_shape(shape_index, color)
}

draw_cubic_bezier :: proc(a, b, c, d: [2]f32, width: f32, color: Color) {
	ab := linalg.lerp(a, b, 0.5)
	cd := linalg.lerp(c, d, 0.5)
	mp := linalg.lerp(ab, cd, 0.5)
	draw_quad_bezier(a, ab, mp, width, color)
	draw_quad_bezier(mp, cd, d, width, color)
}

add_polygon_shape :: proc(pts: ..[2]f32) -> u32 {
	shape := Shape {
		kind  = .Polygon,
		start = u32(len(core.gfx.cvs.data)),
	}
	for p in pts {
		append(&core.gfx.cvs.data, p)
		shape.count += 1
	}
	return add_shape(shape)
}

draw_polygon_fill :: proc(pts: [][2]f32, color: Color) {
	shape := Shape {
		kind  = .Polygon,
		start = u32(len(core.gfx.cvs.data)),
		count = u32(len(pts)),
	}
	append(&core.gfx.cvs.data, ..pts)
	shape_index := add_shape(shape)
	render_shape(shape_index, color)
}

lerp_cubic_bezier :: proc(a, b, c, d: [2]f32, t: f32) -> [2]f32 {
	weights: matrix[4, 4]f32 = {1, 0, 0, 0, -3, 3, 0, 0, 3, -6, 3, 0, -1, 3, -3, 1}
	times: matrix[1, 4]f32 = {1, t, t * t, t * t * t}
	return [2]f32 {
		(times * weights * (matrix[4, 1]f32){a.x, b.x, c.x, d.x})[0][0],
		(times * weights * (matrix[4, 1]f32){a.y, b.y, c.y, d.y})[0][0],
	}
}

draw_pie :: proc(center: [2]f32, from, to, radius: f32, color: Color) {
	from, to := from, to
	if from > to do from, to = to, from
	th0 := -(from + (to - from) * 0.5) + math.PI
	th1 := (to - from) / 2
	render_shape(
		add_shape(
			Shape {
				kind = .Pie,
				cv0 = center,
				cv1 = [2]f32{math.sin(th0), math.cos(th0)},
				cv2 = [2]f32{math.sin(th1), math.cos(th1)},
				radius = radius,
			},
		),
		color,
	)
}

draw_arc :: proc(center: [2]f32, from, to: f32, radius, width: f32, color: Color) {
	from, to := from, to
	if from > to do from, to = to, from
	th0 := -(from + (to - from) * 0.5) + math.PI
	th1 := (to - from) / 2
	render_shape(
		add_shape(
			Shape {
				kind = .Arc,
				cv0 = center,
				cv1 = [2]f32{math.sin(th0), math.cos(th0)},
				cv2 = [2]f32{math.sin(th1), math.cos(th1)},
				radius = radius,
				width = width,
			},
		),
		color,
	)
}

draw_horizontal_box_gradient :: proc(box: Box, left, right: Color) {
	set_paint(0)
	shape := add_shape_box(box, {})
	a := add_vertex(Vertex{pos = box.lo, col = left, shape = shape})
	b := add_vertex(Vertex{pos = {box.lo.x, box.hi.y}, col = left, shape = shape})
	c := add_vertex(Vertex{pos = box.hi, col = right, shape = shape})
	d := add_vertex(Vertex{pos = {box.hi.x, box.lo.y}, col = right, shape = shape})
	add_indices(a, b, c, a, c, d)
}

draw_vertical_box_gradient :: proc(box: Box, top, bottom: Color) {
	set_paint(0)
	shape := add_shape_box(box, {})
	a := add_vertex(Vertex{pos = box.lo, col = top, shape = shape})
	b := add_vertex(Vertex{pos = {box.hi.x, box.lo.y}, col = top, shape = shape})
	c := add_vertex(Vertex{pos = box.hi, col = bottom, shape = shape})
	d := add_vertex(Vertex{pos = {box.lo.x, box.hi.y}, col = bottom, shape = shape})
	add_indices(a, b, c, a, c, d)
}

draw_circle_fill :: proc(center: [2]f32, radius: f32, color: Color) {
	shape_index := add_shape(Shape{kind = .Circle, cv0 = center, radius = radius})
	render_shape(shape_index, color)
}

draw_circle_stroke :: proc(center: [2]f32, radius, width: f32, color: Color) {
	shape_index := add_shape(
		Shape{kind = .Circle, cv0 = center, radius = radius, width = width, stroke = true},
	)
	render_shape(shape_index, color)
}

draw_box_fill :: proc(box: Box, color: Color) {
	render_shape(add_shape_box(box, {}), color)
}

draw_box_stroke :: proc(box: Box, width: f32, color: Color) {
	draw_rounded_box_stroke(box, 0, width, color)
}

// TODO: document corner order
draw_rounded_box_corners_fill :: proc(box: Box, corners: [4]f32, color: Color) {
	if box.hi.x <= box.lo.x || box.hi.y <= box.lo.y {
		return
	}
	render_shape(add_shape_box(box, corners), color)
}

draw_rounded_box_fill :: proc(box: Box, radius: f32, color: Color) {
	if box.hi.x <= box.lo.x || box.hi.y <= box.lo.y {
		return
	}
	render_shape(add_shape_box(box, radius), color)
}

draw_rounded_box_shadow :: proc(box: Box, corner_radius, blur_radius: f32, color: Color) {
	if box.hi.x <= box.lo.x || box.hi.y <= box.lo.y {
		return
	}
	render_shape(
		add_shape(
			Shape {
				kind = .BlurredBox,
				radius = corner_radius,
				cv0 = box.lo,
				cv1 = box.hi,
				cv2 = {0 = blur_radius},
			},
		),
		color,
	)
}

draw_shadow :: proc(box: Box, rounding: f32, opacity: f32 = 1) {
	draw_rounded_box_shadow(
		move_box(box, {0, 1}),
		rounding,
		16,
		fade(core.style.color.shadow, opacity),
	)
}

draw_rounded_box_stroke :: proc(box: Box, radius, width: f32, color: Color) {
	if box.hi.x <= box.lo.x || box.hi.y <= box.lo.y {
		return
	}
	radius := min(radius, (box.hi.x - box.lo.x) / 2, (box.hi.y - box.lo.y) / 2)
	render_shape(
		add_shape(
			Shape {
				kind = .Box,
				corners = radius,
				cv0 = box.lo,
				cv1 = box.hi,
				width = width,
				stroke = true,
			},
		),
		color,
	)
}

draw_spinner :: proc(center: [2]f32, radius: f32, color: Color) {
	from := f32(time.duration_seconds(time.since(core.start_time)) * 2) * math.PI
	to := from + 2.5 + math.sin(f32(time.duration_seconds(time.since(core.start_time)) * 3)) * 1

	width := radius * 0.25

	draw_arc(center, from, to, radius - width / 2, width, color)

	core.draw_next_frame = true
}

draw_arrow :: proc(pos: [2]f32, scale: f32, color: Color) {
	begin_path()
	point(pos + {-1, -0.5} * scale)
	point(pos + {0, 0.5} * scale)
	point(pos + {1, -0.5} * scale)
	stroke_path(2, color)
	end_path()
}

draw_check :: proc(pos: [2]f32, scale: f32, color: Color) {
	begin_path()
	point(pos + {-1, -0.047} * scale)
	point(pos + {-0.333, 0.619} * scale)
	point(pos + {1, -0.713} * scale)
	stroke_path(2, color)
	end_path()
}
