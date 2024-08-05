package onyx

import "core:math"
import "core:math/linalg"

// [SECTION] Paths
clear_path :: proc(path: ^Path) {
	path.count = 0
}

__get_path :: proc() -> ^Path {
	return &core.paths.items[core.paths.height - 1]
}

begin_path :: proc() {
	push(&core.paths, Path{})
}

end_path :: proc() {
	pop(&core.paths)
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
	surface := __get_draw_surface()
	i := u16(len(surface.vertices))
	append(&surface.vertices, 
		Vertex{pos = path.points[0], col = color, z = surface.z},
		)
	for j in 1..<path.count {
		append(&surface.vertices, 
			Vertex{pos = path.points[j], col = color, z = surface.z},
			)
		if j < path.count - 1 {
			append(&surface.indices,
				i,
				i + u16(j),
				i + u16(j) + 1,
				)
		}
	}
}

stroke_path :: proc(thickness: f32, color: Color, justify: Stroke_Justify = .Center) {
	path := __get_path()
	if path.count < 2 {
		return
	}
	surface := __get_draw_surface()
	base_index := u16(len(surface.vertices))
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
			__vertices(surface, 
				Vertex{pos = p1 + (right / dot1) * miter1, col = color, z = surface.z},
				Vertex{pos = p1 - (left / dot1) * miter1, col = color, z = surface.z},
			)
		}

		// End of segment
		__vertices(surface, 
			Vertex{pos = p2 + (right / dot2) * miter2, col = color, z = surface.z},
			Vertex{pos = p2 - (left / dot2) * miter2, col = color, z = surface.z},
		)
		// Join vertices
		if path.closed && i == path.count - 1 {
			// Join to first endpoint
			__indices(surface, 
				base_index + u16(i * 2), 
				base_index + u16(i * 2 + 1), 
				base_index,
				base_index + u16(i * 2 + 1),
				base_index + 1,
				base_index,
				)
		} else if i < path.count - 1 {
			// Join to next endpoint
			__indices(surface, 
				base_index + u16(i * 2),
				base_index + u16(i * 2 + 1),
				base_index + u16(i * 2 + 2),
				base_index + u16(i * 2 + 3),
				base_index + u16(i * 2 + 2),
				base_index + u16(i * 2 + 1),
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

// [SECTION] Draw surfaces
init_draw_surface :: proc(surface: ^Draw_Surface) {
	reserve(&surface.vertices, 8096)
	reserve(&surface.indices, 8096)
}

make_draw_surface :: proc() -> Draw_Surface {
	res: Draw_Surface
	init_draw_surface(&res)
	return res
}

destroy_draw_surface :: proc(surface: ^Draw_Surface) {
	delete(surface.indices)
	delete(surface.vertices)
}

clear_draw_surface :: proc(surface: ^Draw_Surface) {
	clear(&surface.vertices)
	clear(&surface.indices)
}

__get_draw_surface :: proc() -> ^Draw_Surface {
	return core.draw_surface.?
}

destroy_image :: proc(using self: ^Image) {
	delete(data)
}

__vertices :: proc(s: ^Draw_Surface, vertices: ..Vertex) {
	append(&s.vertices, ..vertices)
}

__indices :: proc(s: ^Draw_Surface, indices: ..u16) {
	append(&s.indices, ..indices)
}

/*
	Basic shapes drawn in immediate mode
*/
draw_triangle_fill :: proc(a, b, c: [2]f32, color: Color) {
	surface := __get_draw_surface()
	i := len(surface.vertices)
	__vertices(surface, 
		Vertex{pos = a, col = color},
		Vertex{pos = b, col = color},
		Vertex{pos = c, col = color},
		)
	__indices(surface,
		u16(i),
		u16(i + 1),
		u16(i + 2),
		)
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
			{ a.x - radius.x, a.y - radius.y },
			{ a.x + radius.x, a.y + radius.y },
			{ b.x - radius.x, b.y - radius.y },
			{ b.x + radius.x, b.y + radius.y },
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
	surface := __get_draw_surface()

	from, to := from, to
	if from > to do from, to = to, from
	da := to - from
	nsteps := get_arc_steps(radius, da)

	i := len(surface.vertices)

	__vertices(surface, Vertex{pos = center, col = color})
	for n in 0..=nsteps {
		a := from + da * f32(n) / f32(nsteps)
		j := len(surface.vertices)
		__vertices(surface, 
			Vertex{pos = center + {math.cos(a), math.sin(a)} * radius, col = color},
			)
		if n < nsteps {
			__indices(surface, 
				u16(i), 
				u16(j), 
				u16(j + 1),
				)
		}
	}
}
// Draw a stroke along an arc
draw_arc_stroke :: proc(center: [2]f32, radius, from, to, thickness: f32, color: Color) {
	surface := __get_draw_surface()

	from, to := from, to
	if from > to do from, to = to, from
	da := to - from
	nsteps := get_arc_steps(radius, da)

	i := len(surface.vertices)

	begin_path()
	for n in 0..=nsteps {
		a := from + da * f32(n) / f32(nsteps)
		j := len(surface.vertices)
		point(center + {math.cos(a), math.sin(a)} * radius)
	}
	stroke_path(thickness, color, .Inner)
	end_path()
}
draw_box_fill :: proc(box: Box, color: Color) {
	surface := __get_draw_surface()
	i := len(surface.vertices)
	__vertices(surface, 
		Vertex{pos = box.low, col = color, z = surface.z},
		Vertex{pos = {box.low.x, box.high.y}, col = color, z = surface.z},
		Vertex{pos = box.high, col = color, z = surface.z},
		Vertex{pos = {box.high.x, box.low.y}, col = color, z = surface.z},
		)
	__indices(surface,
		u16(i),
		u16(i + 2),
		u16(i + 1),
		u16(i),
		u16(i + 3),
		u16(i + 2),
		)
}
draw_box_stroke :: proc(box: Box, thickness: f32, color: Color) {
	draw_box_fill({box.low, {box.high.x, box.low.y + thickness}}, color)
	draw_box_fill({{box.low.x, box.high.y - thickness}, box.high}, color)
	draw_box_fill({{box.low.x, box.low.y + thickness}, {box.low.x + thickness, box.high.y - thickness}}, color)
	draw_box_fill({{box.high.x - thickness, box.low.y + thickness}, {box.high.x, box.high.y - thickness}}, color)
}
draw_rounded_box_fill :: proc(box: Box, radius: f32, color: Color) {
	if box.high.x <= box.low.x || box.high.y <= box.low.y {
		return
	}
	radius := min(radius, (box.high.x - box.low.x) / 2, (box.high.y - box.low.y) / 2)
	if radius <= 0 {
		draw_box_fill(box, color)
		return
	}
	draw_arc_fill(box.low + radius, radius, math.PI, math.PI * 1.5, color)
	draw_arc_fill({box.high.x - radius, box.low.y + radius}, radius, math.PI * 1.5, math.PI * 2, color)
	draw_arc_fill(box.high - radius, radius, 0, math.PI * 0.5, color)
	draw_arc_fill({box.low.x + radius, box.high.y - radius}, radius, math.PI * 0.5, math.PI, color)
	if box.high.x - radius > box.low.x + radius {
		draw_box_fill({{box.low.x + radius, box.low.y}, {box.high.x - radius, box.high.y}}, color)
	}
	if box.high.y - radius > box.low.y + radius {
		draw_box_fill({{box.low.x, box.low.y + radius}, {box.low.x + radius, box.high.y - radius}}, color)
		draw_box_fill({{box.high.x - radius, box.low.y + radius}, {box.high.x, box.high.y - radius}}, color)
	}
}

draw_rounded_box_corners_fill :: proc(box: Box, radius: f32, corners: Corners, color: Color) {
	if box.high.x <= box.low.x || box.high.y <= box.low.y {
		return
	}
	radius := min(radius, (box.high.x - box.low.x) / 2, (box.high.y - box.low.y) / 2)
	if radius <= 0 || corners == {} {
		draw_box_fill(box, color)
		return
	}
	if .Top_Left in corners {
		draw_arc_fill(box.low + radius, radius, math.PI, math.PI * 1.5, color)
	} else {
		draw_box_fill({box.low, box.low + radius}, color)
	}
	if .Top_Right in corners {
		draw_arc_fill({box.high.x - radius, box.low.y + radius}, radius, math.PI * 1.5, math.PI * 2, color)
	} else {
		draw_box_fill({{box.high.x - radius, box.low.y}, {box.high.x, box.low.y + radius}}, color)
	}
	if .Bottom_Right in corners {
		draw_arc_fill(box.high - radius, radius, 0, math.PI * 0.5, color)
	} else {
		draw_box_fill({box.high - radius, box.high}, color)
	}
	if .Bottom_Left in corners {
		draw_arc_fill({box.low.x + radius, box.high.y - radius}, radius, math.PI * 0.5, math.PI, color)
	} else {
		draw_box_fill({{box.low.x, box.high.y - radius}, {box.low.x + radius, box.high.y}}, color)
	}
	if box.high.x - radius > box.low.x + radius {
		draw_box_fill({{box.low.x + radius, box.low.y}, {box.high.x - radius, box.high.y}}, color)
	}
	if box.high.y - radius > box.low.y + radius {
		draw_box_fill({{box.low.x, box.low.y + radius}, {box.low.x + radius, box.high.y - radius}}, color)
		draw_box_fill({{box.high.x - radius, box.low.y + radius}, {box.high.x, box.high.y - radius}}, color)
	}
}

draw_rounded_box_stroke :: proc(box: Box, radius, thickness: f32, color: Color) {
	if box.high.x <= box.low.x || box.high.y <= box.low.y {
		return
	}
	radius := min(radius, (box.high.x - box.low.x) / 2, (box.high.y - box.low.y) / 2)
	if radius <= 0 {
		draw_box_stroke(box, thickness, color)
		return
	}
	draw_arc_stroke(box.low + radius, radius, math.PI, math.PI * 1.5, thickness, color)
	draw_arc_stroke({box.high.x - radius, box.low.y + radius}, radius, math.PI * 1.5, math.PI * 2, thickness, color)
	draw_arc_stroke(box.high - radius, radius, 0, math.PI * 0.5, thickness, color)
	draw_arc_stroke({box.low.x + radius, box.high.y - radius}, radius, math.PI * 0.5, math.PI, thickness, color)
	if box.high.x - radius > box.low.x + radius {
		draw_box_fill({{box.low.x + radius, box.low.y}, {box.high.x - radius, box.low.y + thickness}}, color)
		draw_box_fill({{box.low.x + radius, box.high.y - thickness}, {box.high.x - radius, box.high.y}}, color)
	}
	if box.high.y - radius > box.low.y + radius {
		draw_box_fill({{box.low.x, box.low.y + radius}, {box.low.x + thickness, box.high.y - radius}}, color)
		draw_box_fill({{box.high.x - thickness, box.low.y + radius}, {box.high.x, box.high.y - radius}}, color)
	}
}

draw_texture :: proc(source, target: Box, color: Color) {
	surface := __get_draw_surface()
	i := len(surface.vertices)
	tex_size: [2]f32 = {f32(core.atlas.width), f32(core.atlas.height)}
	__vertices(surface, 
		Vertex{
			pos = target.low, 
			col = color, 
			uv = source.low / tex_size,
			z = surface.z,
		},
		Vertex{
			pos = {target.low.x, target.high.y}, 
			col = color, 
			uv = [2]f32{source.low.x, source.high.y} / tex_size,
			z = surface.z,
		},
		Vertex{
			pos = target.high, 
			col = color, 
			uv = source.high / tex_size,
			z = surface.z,
		},
		Vertex{
			pos = {target.high.x, target.low.y}, 
			col = color, 
			uv = [2]f32{source.high.x, source.low.y} / tex_size,
			z = surface.z,
		},
		)
	__indices(surface,
		u16(i),
		u16(i + 2),
		u16(i + 1),
		u16(i),
		u16(i + 3),
		u16(i + 2),
		)
}

foreground :: proc() {
	layout := current_layout()
	draw_rounded_box_fill(layout.box, core.style.rounding, core.style.color.foreground)
	draw_rounded_box_stroke(layout.box, core.style.rounding, 1, core.style.color.substance)
}