package onyx
import "core:math"
import "core:math/linalg"

barycentric :: proc(point, a, b, c: [2]f32) -> (u, v: f32) {
	d := c - a
	e := b - a
	f := point - a
	dd := linalg.dot(d, d)
	ed := linalg.dot(e, d)
	fd := linalg.dot(f, d)
	ee := linalg.dot(e, e)
	fe := linalg.dot(f, e)

	denom := dd * ee - ed * ed
	u = (ee * fd - ed * fe) / denom
	v = (dd * fe - ed * fd) / denom
	return
}

line_closest_point :: proc(a, b, p: [2]f32) -> [2]f32 {
	ap := p - a
	ab_dir := b - a
	dot := ap.x * ab_dir.x + ap.y * ab_dir.y
	if dot < 0 do return a
	ab_len_sqr := ab_dir.x * ab_dir.x + ab_dir.y * ab_dir.y
	if dot > ab_len_sqr do return b
	return a + ab_dir * dot / ab_len_sqr
}

triangle_closest_point :: proc(a, b, c, p: [2]f32) -> [2]f32 {
	proj_ab := line_closest_point(a, b, p)
	proj_bc := line_closest_point(b, c, p)
	proj_ca := line_closest_point(c, a, p)
	dist2_ab := linalg.length2(p - proj_ab)
	dist2_bc := linalg.length2(p - proj_bc)
	dist2_ca := linalg.length2(p - proj_ca)
	m := linalg.min(dist2_ab, linalg.min(dist2_bc, dist2_ca))
	if m == dist2_ab do return proj_ab
	if m == dist2_bc do return proj_bc
	return proj_ca
}

triangle_contains_point :: proc(a, b, c, p: [2]f32) -> bool {
	b1 := ((p.x - b.x) * (a.y - b.y) - (p.y - b.y) * (a.x - b.x)) < 0
	b2 := ((p.x - c.x) * (b.y - c.y) - (p.y - c.y) * (b.x - c.x)) < 0
	b3 := ((p.x - a.x) * (c.y - a.y) - (p.y - a.y) * (c.x - a.x)) < 0
	return (b1 == b2) && (b2 == b3)
}

triangle_barycentric :: proc(a, b, c, p: [2]f32) -> (u, v, w: f32) {
	v0 := b - a
	v1 := c - a
	v2 := p - a
	denom := v0.x * v1.y - v1.x * v0.y
	v = (v2.x * v1.y - v1.x * v2.y) / denom
	w = (v0.x * v2.y - v2.x * v0.y) / denom
	u = 1 - v - w
	return
}

Color_Wheel_Info :: struct {
	using _: Widget_Info,
	hsva:    ^[4]f32,
	changed: bool,
}

init_color_wheel :: proc(using info: ^Color_Wheel_Info) -> bool {
	if info == nil do return false
	if info.hsva == nil do return false
	desired_size = {120, 120}
	fixed_size = true
	sticky = true
	self = get_widget(id) or_return
	return true
}

add_color_wheel :: proc(using info: ^Color_Wheel_Info) -> bool {
	begin_widget(info) or_return
	defer end_widget()

	size := min(box_width(self.box), box_height(self.box))
	outer := size / 2
	inner := outer - 15

	center := box_center(self.box)
	angle := hsva.x * math.RAD_PER_DEG

	TRIANGLE_STEP :: math.TAU / 3

	// Three points of the inner triangle
	// Hue point
	point_a: [2]f32 = center + {math.cos(angle), math.sin(angle)} * inner
	// Black point
	point_b: [2]f32 =
		center + {math.cos(angle - TRIANGLE_STEP), math.sin(angle - TRIANGLE_STEP)} * inner
	// White point
	point_c: [2]f32 =
		center + {math.cos(angle + TRIANGLE_STEP), math.sin(angle + TRIANGLE_STEP)} * inner

	diff := core.mouse_pos - center
	dist := linalg.length(diff)

	if dist <= outer {
		hover_widget(self)
	}

	if .Pressed in (self.state - self.last_state) {
		if dist > inner {
			self.state += {.Active}
		}
	} else if .Pressed in self.state {
		if .Active in self.state {
			// Hue assignment
			hsva.x = math.atan2(diff.y, diff.x) / math.RAD_PER_DEG
			if hsva.x < 0 {
				hsva.x += 360
			}
		} else {
			point := core.mouse_pos
			if !triangle_contains_point(point_a, point_b, point_c, point) {
				point = triangle_closest_point(point_a, point_b, point_c, point)
			}
			u, v, w := triangle_barycentric(point_a, point_b, point_c, point)
			hsva.z = clamp(1 - v, 0.0001, 1)
			hsva.y = clamp(u / hsva.z, 0.0001, 1)
			draw_arc_fill(point, 4, 0, math.TAU, {255, 0, 255, 255})
		}
		changed = true
	} else {
		self.state -= {.Active}
	}

	if self.visible {
		// H wheel
		STEP :: math.TAU / 48.0
		for t: f32 = 0; t < math.TAU; t += STEP {
			normal := [2]f32{math.cos(t), math.sin(t)}
			next_normal := [2]f32{math.cos(t + STEP), math.sin(t + STEP)}
			set_vertex_color(color_from_hsva({t * math.DEG_PER_RAD, 1, 1, 1}))
			index_0, index_1 :=
				add_vertex(center + normal * outer), add_vertex(center + normal * inner)
			set_vertex_color(color_from_hsva({(t + STEP) * math.DEG_PER_RAD, 1, 1, 1}))
			index_2, index_3 :=
				add_vertex(center + next_normal * inner), add_vertex(center + next_normal * outer)
			add_indices(index_0, index_1, index_2, index_0, index_2, index_3)
		}

		angle := hsva.x * math.RAD_PER_DEG
		// Hue point
		point_a = center + {math.cos(angle), math.sin(angle)} * inner
		// Black point
		point_b =
			center + {math.cos(angle - TRIANGLE_STEP), math.sin(angle - TRIANGLE_STEP)} * inner
		// White point
		point_c =
			center + {math.cos(angle + TRIANGLE_STEP), math.sin(angle + TRIANGLE_STEP)} * inner

		// SV triangle
		set_vertex_color(color_from_hsva({hsva.x, 1, 1, 1}))
		index_a := add_vertex(point_a)
		set_vertex_color({0, 0, 0, 255})
		index_b := add_vertex(point_b)
		set_vertex_color(255)
		index_c := add_vertex(point_c)
		add_indices(index_a, index_b, index_c)

		// SV circle
		point := linalg.lerp(linalg.lerp(point_c, point_a, clamp(hsva.y, 0, 1)), point_b, clamp(1 - hsva.z, 0, 1))
		r: f32 = 7 if (self.state >= {.Pressed} && .Active not_in self.state) else 5
		draw_arc_fill(point, r, 0, math.TAU, color_from_hsva({hsva.x, hsva.y, hsva.z, 1}))
		draw_ring_fill(
			point,
			r - 1,
			r,
			0,
			math.TAU,
			{0, 0, 0, 255} if hsva.z > 0.5 else 255,
		)
	}

	return true
}

color_wheel :: proc(info: Color_Wheel_Info, loc := #caller_location) -> Color_Wheel_Info {
	info := info
	info.id = hash(loc)
	if init_color_wheel(&info) {
		add_color_wheel(&info)
	}
	return info
}
