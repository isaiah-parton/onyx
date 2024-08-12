package onyx

import "core:fmt"
import "core:math"
import "core:math/linalg"



clear_path :: proc(path: ^Path) {
	path.count = 0
}

__get_path :: proc() -> ^Path {
	return &core.path_stack.items[core.path_stack.height - 1]
}

begin_path :: proc() {
	push_stack(&core.path_stack, Path{})
}

end_path :: proc() {
	pop_stack(&core.path_stack)
}

close_path :: proc() {
	__get_path().closed = true
}

point :: proc(point: [2]f32) {
	path := __get_path()
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
		weights: matrix[4, 4]f32 = {
			1, 0, 0, 0,
			-3, 3, 0, 0,
			3, -6, 3, 0,
			-1, 3, -3, 1,
		}
		point({
			(times * weights * (matrix[4, 1]f32){p0.x, p1.x, p2.x, p3.x})[0][0],
			(times * weights * (matrix[4, 1]f32){p0.y, p1.y, p2.y, p3.y})[0][0],
		})
	}
}

arc :: proc(center: [2]f32, radius, from, to: f32) {
	da := to - from
	nsteps := int(abs(da) / ANGLE_TOLERANCE)
	for n in 1..<nsteps {
		a := from + da * f32(n) / f32(nsteps)
		point(center + {math.cos(a), math.sin(a)} * radius)
	}
}

fill_path :: proc(color: Color) {
	path := __get_path()
	if path.count < 3 {
		return
	}
	index := add_vertex(path.points[0])
	for i in 1..<path.count {
		add_vertex(path.points[i])
		if i < path.count - 1 {
			add_indices(
				index,
				index + u16(i),
				index + u16(i) + 1,
				)
		}
	}
}

stroke_path :: proc(thickness: f32, color: Color, justify: Stroke_Justify = .Center) {
	path := __get_path()

	if path.count < 2 {
		return
	}

	first_index := u16(len(core.current_draw_call.vertices))

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

	core.vertex_state.col = color
	core.vertex_state.uv = {}

	for i in 0..<path.count {
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
			
			add_vertex(p1 + (right / dot1) * miter1)
			add_vertex(p1 - (left / dot1) * miter1)
		}

		// End of segment
		add_vertex(p2 + (right / dot2) * miter2)
		add_vertex(p2 - (left / dot2) * miter2)
		// Join vertices
		if path.closed && i == path.count - 1 {
			// Join to first endpoint
			add_indices( 
				first_index + u16(i * 2), 
				first_index + u16(i * 2 + 1), 
				first_index,
				first_index + u16(i * 2 + 1),
				first_index + 1,
				first_index,
				)
		} else if i < path.count - 1 {
			// Join to next endpoint
			add_indices( 
				first_index + u16(i * 2),
				first_index + u16(i * 2 + 1),
				first_index + u16(i * 2 + 2),
				first_index + u16(i * 2 + 3),
				first_index + u16(i * 2 + 2),
				first_index + u16(i * 2 + 1),
				)
		}
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

/*
	Basic shapes drawn in immediate mode
*/
draw_triangle_fill :: proc(a, b, c: [2]f32, color: Color) {
	core.vertex_state = {
		col = color,
	}
	add_index(add_vertex(a.x, a.y))
	add_index(add_vertex(b.x, b.y))
	add_index(add_vertex(c.x, c.y))
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
draw_line :: proc(a, b: [2]f32, thickness: f32, color: Color) {
	delta := b - a
	length := math.sqrt(f32(delta.x * delta.x + delta.y * delta.y))
	if length > 0 && thickness > 0 {
		scale := thickness / (2 * length)
		radius: [2]f32 = {-scale * delta.y, scale * delta.x}
		draw_triangle_strip_fill({
			{ a.x + radius.x, a.y + radius.y },
			{ a.x - radius.x, a.y - radius.y },
			{ b.x + radius.x, b.y + radius.y },
			{ b.x - radius.x, b.y - radius.y },
		}, color)
	}
}

draw_bezier_stroke :: proc(p0, p1, p2, p3: [2]f32, segments: int, thickness: f32, color: Color) {
	step: f32 = 1.0 / f32(segments)
	lp: [2]f32 = p0
	for t: f32 = step; t <= 1; t += step {
		times: matrix[1, 4]f32 = {1, t, t * t, t * t * t}
		weights: matrix[4, 4]f32 = {
			1, 0, 0, 0,
			-3, 3, 0, 0,
			3, -6, 3, 0,
			-1, 3, -3, 1,
		}
		p: [2]f32 = {
			(times * weights * (matrix[4, 1]f32){p0.x, p1.x, p2.x, p3.x})[0][0],
			(times * weights * (matrix[4, 1]f32){p0.y, p1.y, p2.y, p3.y})[0][0],
		}
		draw_line(lp, p, thickness, color)
		lp = p
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

	core.vertex_state.col = color
	core.vertex_state.uv = {}
	first_index := add_vertex(center.x, center.y)
	for n in 0..=nsteps {
		a := from + da * f32(n) / f32(nsteps)
		index := add_vertex(center + {math.cos(a), math.sin(a)} * radius)
		if n < nsteps {
			add_indices(first_index, index, index + 1)
		}
	}
}
// Draw a stroke along an arc
draw_arc_stroke :: proc(center: [2]f32, radius, from, to, thickness: f32, color: Color) {
	from, to := from, to
	if from > to do from, to = to, from
	da := to - from
	nsteps := get_arc_steps(radius, da)

	begin_path()
	for n in 0..=nsteps {
		a := from + da * f32(n) / f32(nsteps)
		point(center + {math.cos(a), math.sin(a)} * radius)
	}
	stroke_path(thickness, color, .Inner)
	end_path()
}
draw_box_fill :: proc(box: Box, color: Color) {
	core.vertex_state.col = color
	core.vertex_state.uv = {}
	tl := add_vertex(box.lo)
	bl := add_vertex({box.lo.x, box.hi.y})
	br := add_vertex(box.hi)
	tr := add_vertex({box.hi.x, box.lo.y})
	add_indices(tl, br, bl, tl, tr, br)
}
draw_box_stroke :: proc(box: Box, thickness: f32, color: Color) {
	draw_box_fill({box.lo, {box.hi.x, box.lo.y + thickness}}, color)
	draw_box_fill({{box.lo.x, box.hi.y - thickness}, box.hi}, color)
	draw_box_fill({{box.lo.x, box.lo.y + thickness}, {box.lo.x + thickness, box.hi.y - thickness}}, color)
	draw_box_fill({{box.hi.x - thickness, box.lo.y + thickness}, {box.hi.x, box.hi.y - thickness}}, color)
}
draw_rounded_box_fill :: proc(box: Box, radius: f32, color: Color) {
	if box.hi.x <= box.lo.x || box.hi.y <= box.lo.y {
		return
	}
	radius := min(radius, (box.hi.x - box.lo.x) / 2, (box.hi.y - box.lo.y) / 2)
	if radius <= 0 {
		draw_box_fill(box, color)
		return
	}
	draw_arc_fill(box.lo + radius, radius, math.PI, math.PI * 1.5, color)
	draw_arc_fill({box.hi.x - radius, box.lo.y + radius}, radius, math.PI * 1.5, math.PI * 2, color)
	draw_arc_fill(box.hi - radius, radius, 0, math.PI * 0.5, color)
	draw_arc_fill({box.lo.x + radius, box.hi.y - radius}, radius, math.PI * 0.5, math.PI, color)
	if box.hi.x - radius > box.lo.x + radius {
		draw_box_fill({{box.lo.x + radius, box.lo.y}, {box.hi.x - radius, box.hi.y}}, color)
	}
	if box.hi.y - radius > box.lo.y + radius {
		draw_box_fill({{box.lo.x, box.lo.y + radius}, {box.lo.x + radius, box.hi.y - radius}}, color)
		draw_box_fill({{box.hi.x - radius, box.lo.y + radius}, {box.hi.x, box.hi.y - radius}}, color)
	}
}

draw_rounded_box_corners_fill :: proc(box: Box, radius: f32, corners: Corners, color: Color) {
	if box.hi.x <= box.lo.x || box.hi.y <= box.lo.y {
		return
	}
	radius := min(radius, (box.hi.x - box.lo.x) / 2, (box.hi.y - box.lo.y) / 2)
	if radius <= 0 || corners == {} {
		draw_box_fill(box, color)
		return
	}
	if .Top_Left in corners {
		draw_arc_fill(box.lo + radius, radius, math.PI, math.PI * 1.5, color)
	} else {
		draw_box_fill({box.lo, box.lo + radius}, color)
	}
	if .Top_Right in corners {
		draw_arc_fill({box.hi.x - radius, box.lo.y + radius}, radius, math.PI * 1.5, math.PI * 2, color)
	} else {
		draw_box_fill({{box.hi.x - radius, box.lo.y}, {box.hi.x, box.lo.y + radius}}, color)
	}
	if .Bottom_Right in corners {
		draw_arc_fill(box.hi - radius, radius, 0, math.PI * 0.5, color)
	} else {
		draw_box_fill({box.hi - radius, box.hi}, color)
	}
	if .Bottom_Left in corners {
		draw_arc_fill({box.lo.x + radius, box.hi.y - radius}, radius, math.PI * 0.5, math.PI, color)
	} else {
		draw_box_fill({{box.lo.x, box.hi.y - radius}, {box.lo.x + radius, box.hi.y}}, color)
	}
	if box.hi.x - radius > box.lo.x + radius {
		draw_box_fill({{box.lo.x + radius, box.lo.y}, {box.hi.x - radius, box.hi.y}}, color)
	}
	if box.hi.y - radius > box.lo.y + radius {
		draw_box_fill({{box.lo.x, box.lo.y + radius}, {box.lo.x + radius, box.hi.y - radius}}, color)
		draw_box_fill({{box.hi.x - radius, box.lo.y + radius}, {box.hi.x, box.hi.y - radius}}, color)
	}
}

draw_rounded_box_stroke :: proc(box: Box, radius, thickness: f32, color: Color) {
	if box.hi.x <= box.lo.x || box.hi.y <= box.lo.y {
		return
	}
	radius := min(radius, (box.hi.x - box.lo.x) / 2, (box.hi.y - box.lo.y) / 2)
	if radius <= 0 {
		draw_box_stroke(box, thickness, color)
		return
	}
	draw_arc_stroke(box.lo + radius, radius, math.PI, math.PI * 1.5, thickness, color)
	draw_arc_stroke({box.hi.x - radius, box.lo.y + radius}, radius, math.PI * 1.5, math.PI * 2, thickness, color)
	draw_arc_stroke(box.hi - radius, radius, 0, math.PI * 0.5, thickness, color)
	draw_arc_stroke({box.lo.x + radius, box.hi.y - radius}, radius, math.PI * 0.5, math.PI, thickness, color)
	if box.hi.x - radius > box.lo.x + radius {
		draw_box_fill({{box.lo.x + radius, box.lo.y}, {box.hi.x - radius, box.lo.y + thickness}}, color)
		draw_box_fill({{box.lo.x + radius, box.hi.y - thickness}, {box.hi.x - radius, box.hi.y}}, color)
	}
	if box.hi.y - radius > box.lo.y + radius {
		draw_box_fill({{box.lo.x, box.lo.y + radius}, {box.lo.x + thickness, box.hi.y - radius}}, color)
		draw_box_fill({{box.hi.x - thickness, box.lo.y + radius}, {box.hi.x, box.hi.y - radius}}, color)
	}
}

foreground :: proc() {
	layout := current_layout()
	draw_rounded_box_fill(layout.box, core.style.rounding, core.style.color.foreground)
	draw_rounded_box_stroke(layout.box, core.style.rounding, 1, core.style.color.substance)
}
