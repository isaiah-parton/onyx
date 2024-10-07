package onyx

import "core:fmt"
import "core:math"
import "core:math/ease"
import "core:math/linalg"
import "core:time"

ANGLE_TOLERANCE :: 0.01

add_shape_box :: proc(box: Box, corners: [4]f32) -> u32 {
	return add_shape(
		Shape {
			kind = .Box,
			corners = corners,
			cv0 = transform_point(box.lo),
			cv1 = transform_point(box.hi),
		},
	)
}

add_shape_circle :: proc(center: [2]f32, radius: f32) -> u32 {
	index := u32(len(core.draw_list.shapes))
	append(&core.draw_list.shapes, Shape{kind = .Circle, cv0 = center, radius = radius})
	return index
}

add_shape :: proc(shape: Shape) -> u32 {
	index := u32(len(core.draw_list.shapes))
	shape := shape
	shape.paint = core.draw_state.paint
	shape.scissor = core.draw_state.scissor
	append(&core.draw_list.shapes, shape)
	return index
}

get_shape_bounding_box :: proc(shape: Shape) -> Box {
	box: Box = {math.F32_MAX, 0}
	switch shape.kind {
	case .Normal:
	case .Box:
		box.lo = shape.cv0
		box.hi = shape.cv1
	case .Circle:
		box.lo = shape.cv0 - shape.radius
		box.hi = shape.cv0 + shape.radius
	case .Path:
		for i in 0 ..< shape.count {
			j := shape.start + i
			box.lo = linalg.min(box.lo, core.draw_list.cvs[j])
			box.hi = linalg.max(box.hi, core.draw_list.cvs[j])
		}
	case .Polygon:
		for i in 0 ..< shape.count {
			j := shape.start + i
			box.lo = linalg.min(box.lo, core.draw_list.cvs[j])
			box.hi = linalg.max(box.hi, core.draw_list.cvs[j])
		}
		box.lo -= 1
		box.hi += 1
	case .Bezier:
		box.lo = linalg.min(shape.cv0, shape.cv1, shape.cv2) - shape.width * 2
		box.hi = linalg.max(shape.cv0, shape.cv1, shape.cv2) + shape.width * 2
	case .BlurredBox:
		box.lo = shape.cv0 - shape.cv1 * 3
		box.hi = shape.cv0 + shape.cv1 * 3
	case .Curve:
	}
	if clip, ok := current_clip().?; ok {
		box.lo = linalg.max(box.lo, clip.lo)
		box.hi = linalg.min(box.hi, clip.hi)
	}
	return box
}

render_shape :: proc(shape: u32, color: Color) {
	box := get_shape_bounding_box(core.draw_list.shapes[shape])
	set_vertex_shape(shape)
	set_vertex_color(color)
	set_vertex_uv({})
	a := add_vertex(box.lo)
	b := add_vertex({box.lo.x, box.hi.y})
	c := add_vertex(box.hi)
	d := add_vertex({box.hi.x, box.lo.y})
	add_indices(a, b, c, a, c, d)
	set_vertex_shape(0)
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
	path := get_path()
	if path.count < 3 {
		return
	}
	index := add_vertex(path.points[0])
	for i in 1 ..< path.count {
		add_vertex(path.points[i])
		if i < path.count - 1 {
			add_indices(index, index + u32(i), index + u32(i) + 1)
		}
	}
}

stroke_path :: proc(thickness: f32, color: Color, justify: Stroke_Justify = .Center) {
	path := get_path()

	if path.count < 2 {
		return
	}

	first_index := next_vertex_index()

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

draw_inner_box_shadow :: proc(box: Box, radius, size: f32, colors: [2]Color) {
	set_paint(
		add_paint(
			Paint {
				kind = .Inner_Gradient,
				col0 = normalize_color(colors[0]),
				col1 = normalize_color(colors[1]),
				size = size,
			},
		),
	)
	render_shape(add_shape_box(box, radius), {255, 255, 255, 255})
	set_paint(0)
}

/*
	Basic shapes drawn in immediate mode
*/
draw_triangle_fill :: proc(a, b, c: [2]f32, color: Color) {
	draw_polygon_fill({a, b, c}, color)
}
draw_triangle_strip_fill :: proc(points: [][2]f32, color: Color) {
	if len(points) < 4 {
		return
	}
	for i in 2 ..< len(points) {
		if i % 2 == 0 {
			draw_triangle_fill(
				{points[i].x, points[i].y},
				{points[i - 2].x, points[i - 2].y},
				{points[i - 1].x, points[i - 1].y},
				color,
			)
		} else {
			draw_triangle_fill(
				{points[i].x, points[i].y},
				{points[i - 1].x, points[i - 1].y},
				{points[i - 2].x, points[i - 2].y},
				color,
			)
		}
	}
}
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

draw_quad_bezier :: proc(p0, p1, p2: [2]f32, width: f32, color: Color) {
	// width := width - 1
	shape_index := add_shape(Shape{kind = .Bezier, cv0 = p0, cv1 = p1, cv2 = p2, width = width})
	render_shape(shape_index, color)
}

draw_curve :: proc(pts: [][2]f32, width: f32, color: Color) {
	box := Box{math.F32_MAX, 0}

	prim := u32(len(core.draw_list.shapes))
	append(
		&core.draw_list.shapes,
		Shape {
			kind = .Curve,
			start = u32(len(core.draw_list.cvs)),
			count = u32(len(pts) / 3) + 1,
			width = width,
		},
	)

	for p in pts {
		box.lo = linalg.min(box.lo, p)
		box.hi = linalg.max(box.hi, p)
	}

	append(&core.draw_list.cvs, ..pts)

	set_vertex_shape(prim)
	draw_box_fill(box, color)
	set_vertex_shape(0)
}

draw_cubic_bezier :: proc(a, b, c, d: [2]f32, width: f32, color: Color) {
	ab := linalg.lerp(a, b, 0.5)
	cd := linalg.lerp(c, d, 0.5)
	mp := linalg.lerp(ab, cd, 0.5)
	draw_quad_bezier(a, ab, mp, width, color)
	draw_quad_bezier(mp, cd, d, width, color)
}

add_polygon_shape :: proc(pts: ..[2]f32) -> u32 {
	prim_index := u32(len(core.draw_list.shapes))
	prim := Shape {
		kind  = .Polygon,
		start = u32(len(core.draw_list.cvs)),
	}
	for p in pts {
		append(&core.draw_list.cvs, p)
		prim.count += 1
	}
	append(&core.draw_list.shapes, prim)
	return prim_index
}

draw_polygon_fill :: proc(pts: [][2]f32, color: Color) {
	shape := Shape {
		kind  = .Polygon,
		start = u32(len(core.draw_list.cvs)),
		count = u32(len(pts)),
	}
	append(&core.draw_list.cvs, ..pts)
	shape_index := add_shape(shape)
	render_shape(shape_index, color)
}

lerp_cubic_bezier :: proc(p0, p1, p2, p3: [2]f32, t: f32) -> [2]f32 {
	weights: matrix[4, 4]f32 = {1, 0, 0, 0, -3, 3, 0, 0, 3, -6, 3, 0, -1, 3, -3, 1}
	times: matrix[1, 4]f32 = {1, t, t * t, t * t * t}
	return [2]f32 {
		(times * weights * (matrix[4, 1]f32){p0.x, p1.x, p2.x, p3.x})[0][0],
		(times * weights * (matrix[4, 1]f32){p0.y, p1.y, p2.y, p3.y})[0][0],
	}
}

get_arc_steps :: proc(radius, angle: f32) -> int {
	return max(int((angle / (math.PI * 0.1)) * (radius * 0.25)), 4)
}
// Draw a filled arc around a given center
draw_arc_fill :: proc(center: [2]f32, radius, from, to: f32, color: Color) {
	from, to := from, to
	if from > to do from, to = to, from
	da := to - from
	nsteps := get_arc_steps(radius, da)

	set_vertex_color(color)
	set_vertex_uv({})
	first_index := add_vertex(center.x, center.y)
	for n in 0 ..= nsteps {
		a := from + da * f32(n) / f32(nsteps)
		index := add_vertex(center + {math.cos(a), math.sin(a)} * radius)
		if n < nsteps {
			add_indices(first_index, index, index + 1)
		}
	}
}

draw_horizontal_box_gradient :: proc(box: Box, left, right: Color) {
	set_vertex_uv({})
	set_vertex_color(left)
	tl := add_vertex(box.lo)
	bl := add_vertex({box.lo.x, box.hi.y})
	set_vertex_color(right)
	br := add_vertex(box.hi)
	tr := add_vertex({box.hi.x, box.lo.y})
	add_indices(tl, br, bl, tl, tr, br)
}

draw_circle_fill :: proc(center: [2]f32, radius: f32, color: Color) {
	shape_index := add_shape(Shape{kind = .Circle, cv0 = center, radius = radius})
	render_shape(shape_index, color)
}

draw_ring_fill :: proc(center: [2]f32, inner, outer, from, to: f32, color: Color) {
	from, to := from, to
	if from > to do from, to = to, from
	da := to - from
	nsteps := get_arc_steps(outer, da)
	step := da / f32(nsteps)

	core.vertex_state.uv = {}
	core.vertex_state.col = color

	last_inner_index := add_vertex(center + {1, 0} * inner)
	last_outer_index := add_vertex(center + {1, 0} * outer)
	for n in 0 ..= nsteps {
		angle := from + f32(n) * step
		inner_index := add_vertex(center + {math.cos(angle), math.sin(angle)} * inner)
		outer_index := add_vertex(center + {math.cos(angle), math.sin(angle)} * outer)
		if n > 0 {
			add_indices(
				last_inner_index,
				last_outer_index,
				outer_index,
				last_inner_index,
				outer_index,
				inner_index,
			)
		}
		last_inner_index = inner_index
		last_outer_index = outer_index
	}
}

// Draw a stroke along an arc
draw_arc_stroke :: proc(center: [2]f32, radius, from, to, thickness: f32, color: Color) {
	from, to := from, to
	if from > to do from, to = to, from
	da := to - from
	nsteps := get_arc_steps(radius, da)

	set_vertex_color(color)
	set_vertex_uv({})
	first_index := add_vertex(center.x, center.y)
	last_inner, last_outer: u32
	for n in 0 ..= nsteps {
		a := from + da * f32(n) / f32(nsteps)
		norm := [2]f32{math.cos(a), math.sin(a)}
		inner := add_vertex(center + norm * (radius - thickness))
		outer := add_vertex(center + norm * radius)
		if n > 0 {
			add_indices(last_outer, outer, last_inner, outer, inner, last_inner)
		}
		last_inner, last_outer = inner, outer
	}
}
draw_box_fill :: proc(box: Box, color: Color) {
	render_shape(add_shape_box(box, {}), color)
}
draw_box_fill_clipped :: proc(box: Box, color: Color) {
	box := box
	if clip, ok := current_clip().?; ok {
		box.lo = linalg.max(box.lo, clip.lo)
		box.hi = linalg.min(box.hi, clip.hi)
		if box.lo.x >= box.hi.x || box.lo.y >= box.hi.y do return
	}
	draw_box_fill(box, color)
}
draw_box_stroke :: proc(box: Box, width: f32, color: Color) {
	draw_rounded_box_stroke(box, 0, width, color)
}

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
	corner_radius := min(corner_radius, (box.hi.x - box.lo.x) / 2, (box.hi.y - box.lo.y) / 2)

	shape_index := u32(len(core.draw_list.shapes))
	append(
		&core.draw_list.shapes,
		Shape {
			kind = .BlurredBox,
			radius = corner_radius,
			cv0 = transform_point(box.lo),
			cv1 = transform_point(box.hi),
			cv2 = {0 = blur_radius},
		},
	)

	render_shape(shape_index, color)
}

draw_rounded_box_stroke :: proc(box: Box, radius, width: f32, color: Color) {
	if box.hi.x <= box.lo.x || box.hi.y <= box.lo.y {
		return
	}
	radius := min(radius, (box.hi.x - box.lo.x) / 2, (box.hi.y - box.lo.y) / 2)

	shape_index := u32(len(core.draw_list.shapes))
	append(
		&core.draw_list.shapes,
		Shape {
			kind = .Box,
			corners = radius,
			cv0 = transform_point(box.lo),
			cv1 = transform_point(box.hi),
			width = width,
			stroke = true,
		},
	)

	render_shape(shape_index, color)
}

// lil guys

draw_spinner :: proc(center: [2]f32, color: Color) {
	from := f32(time.duration_seconds(time.since(core.start_time)) * 2) * math.PI
	to := from + 2.5 + math.sin(f32(time.duration_seconds(time.since(core.start_time)) * 3)) * 1

	inner := f32(7)
	outer := f32(10)
	half := (inner + outer) / 2

	draw_ring_fill(center, inner, outer, from, to, color)
	draw_arc_fill(
		center + {math.cos(from), math.sin(from)} * half,
		(outer - inner) / 2,
		0,
		math.TAU,
		color,
	)
	draw_arc_fill(
		center + {math.cos(to), math.sin(to)} * half,
		(outer - inner) / 2,
		0,
		math.TAU,
		color,
	)

	core.draw_next_frame = true
}

draw_loader :: proc(pos: [2]f32, scale: f32, color: Color) {
	time := f32(time.duration_seconds(time.since(core.start_time))) * 4.5
	radius := scale / 2
	center := [2]f32{pos.x + math.cos(time) * scale, pos.y}
	size := [2]f32{radius * (1 + math.abs(math.cos(time + math.PI / 2)) * 0.75), radius}
	draw_rounded_box_fill({center - size, center + size}, scale, color)
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
