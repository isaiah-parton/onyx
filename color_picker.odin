package onyx

import "../vgo"
import "core:fmt"
import "core:math"
import "core:math/ease"
import "core:math/linalg"
import "core:strconv"
import "core:strings"

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

draw_checkerboard_pattern :: proc(box: Box, size: [2]f32, primary, secondary: vgo.Color) {
	vgo.fill_box(box, paint = primary)
	for x in 0 ..< int(math.ceil(box_width(box) / size.x)) {
		for y in 0 ..< int(math.ceil(box_height(box) / size.y)) {
			if (x + y) % 2 == 0 {
				pos := box.lo + [2]f32{f32(x), f32(y)} * size
				vgo.fill_box({pos, linalg.min(pos + size, box.hi)}, paint = secondary)
			}
		}
	}
}

Color_Picker :: struct {
	using object: ^Object,
	hsva:         [4]f32,
	value:        vgo.Color,
	open_time:    f32,
}

color_picker :: proc(value: ^vgo.Color, show_alpha: bool = true, loc := #caller_location) -> Id {
	id := hash(loc)
	object := persistent_object(id)
	object.placement = next_user_placement()
	object.metrics.desired_size = global_state.style.visual_size * {0.5, 1}
	if object.variant == nil {
		object.variant = Color_Picker {
			object = object,
		}
	}
	if begin_object(object) {
		defer end_object()

		self := &object.variant.(Color_Picker)
		if .Changed in self.state.previous {
			value^ = self.value
			draw_frames(1)
		} else {
			self.value = value^
		}
	}
	return id
}

display_color_picker :: proc(self: ^Color_Picker) {

	handle_object_click(self)

	if .Open in self.state.current {
		self.open_time = animate(self.open_time, 0.3, true)
	} else {
		self.open_time = 0
	}
	if .Pressed in new_state(self.state) {
		self.state.current += {.Open}
	}
	if .Hovered in self.state.current {
		global_state.cursor_type = .Pointing_Hand
	}
	if point_in_box(global_state.mouse_pos, self.box) {
		hover_object(self)
	}

	if object_is_visible(self) {
		shadow_opacity := f32(1) //max(object.hover_time, object.open_time)
		if shadow_opacity > 0 {
			vgo.box_shadow(
				self.box,
				global_state.style.rounding,
				6,
				vgo.fade(global_state.style.color.shadow, shadow_opacity),
			)
		}

		checker_box := shrink_box(self.box, 1)
		vgo.push_scissor(vgo.make_box(checker_box, box_height(checker_box) / 2))
		draw_checkerboard_pattern(
			self.box,
			box_height(self.box) / 2,
			vgo.blend(global_state.style.color.checker_bg[0], self.value, vgo.WHITE),
			vgo.blend(global_state.style.color.checker_bg[1], self.value, vgo.WHITE),
		)
		vgo.fill_text(
			fmt.tprintf("#%6x", vgo.hex_from_color(self.value)),
			global_state.style.default_text_size,
			box_center(self.box),
			align = 0.5,
			paint = vgo.BLACK if max(vgo.luminance_of(self.value), 1 - f32(self.value.a) / 255) > 0.45 else vgo.WHITE,
		)
		vgo.pop_scissor()
	}

	PADDING :: 10
	if .Open in self.state.current {
		if .Open not_in self.state.previous {
			self.hsva = vgo.hsva_from_color(self.value)
		}

		push_id(self.id)
		defer pop_id()

		if begin_layer(options = {.Attached}, kind = .Background) {
			defer end_layer()

			if begin_layout(
				axis = .X,
				placement = Future_Box_Placement {
					origin = {
						self.box.hi.x + global_state.style.popup_margin,
						box_center_y(self.box),
					},
					align = {0, 0.5},
				},
				padding = 10,
				isolated = true,
				clip_contents = true,
			) {
				defer end_layout()

				foreground()
				alpha_slider(&self.hsva.w)
				set_margin(left = 10)
				hsv_wheel((^[3]f32)(&self.hsva))
			}

			if object_was_just_changed(last_object().?) {
				self.value = vgo.color_from_hsva(self.hsva)
				self.state.current += {.Changed}
			}

			if .Focused not_in current_layer().?.state && .Focused not_in self.state.current {
				self.state.current -= {.Open}
			}
		}
	}
}

Alpha_Slider :: struct {
	using object: ^Object,
	value:        f32,
	axis:         Axis,
	color:        vgo.Color,
}

alpha_slider :: proc(
	value: ^f32,
	color: vgo.Color = vgo.BLACK,
	axis: Axis = .Y,
	loc := #caller_location,
) -> Id {
	id := hash(loc)
	object := persistent_object(id)
	if object.variant == nil {
		object.variant = Alpha_Slider {
			object = object,
		}
	}
	self := &object.variant.(Alpha_Slider)
	self.placement = next_user_placement()
	self.metrics.desired_size = global_state.style.visual_size
	if self.axis == .Y {
		self.metrics.desired_size.xy = self.metrics.desired_size.yx
	}
	if begin_object(object) {
		defer end_object()

		self.axis = axis
		self.color = color

		if .Changed in self.state.previous {
			value^ = self.value
		}
		self.value = value^
	}
	return id
}

display_alpha_slider :: proc(self: ^Alpha_Slider) {

	handle_object_click(self, true)

	i := int(self.axis)
	j := 1 - i

	if .Pressed in self.state.current {
		self.value = clamp(
			(global_state.mouse_pos[i] - self.box.lo[i]) / (self.box.hi[i] - self.box.lo[i]),
			0,
			1,
		)
		self.state.current += {.Changed}
	}

	if object_is_visible(self) {
		R :: 4
		box := self.box
		draw_checkerboard_pattern(
			box,
			(box.hi[j] - box.lo[j]) / 2,
			global_state.style.color.checker_bg[0],
			global_state.style.color.checker_bg[1],
		)
		self.color.a = 255
		time := clamp(self.value, 0, 1)
		pos := box.lo[i] + (box.hi[i] - box.lo[i]) * time
		if self.axis == .Y {
			vgo.fill_box(
				box,
				paint = vgo.make_linear_gradient(
					box.lo,
					{box.lo.x, box.hi.y},
					vgo.fade(self.color, 0.0),
					self.color,
				),
			)
			vgo.fill_box(
				{{box.lo.x, pos - 1}, {box.hi.x, pos + 1}},
				paint = global_state.style.color.content,
			)
		}
	}

	if point_in_box(global_state.mouse_pos, self.box) {
		hover_object(self)
	}
}

HSV_Wheel :: struct {
	using object: ^Object,
	value:        [3]f32,
}

hsv_wheel :: proc(value: ^[3]f32, loc := #caller_location) -> Id {
	id := hash(loc)
	object := persistent_object(id)
	if object.variant == nil {
		object.variant = HSV_Wheel {
			object = object,
		}
	}
	self := &object.variant.(HSV_Wheel)
	self.placement = next_user_placement()
	self.metrics.desired_size = 200
	if begin_object(object) {
		defer end_object()
		if .Changed in self.state.previous {
			value^ = self.value
		}
		self.value = value^
	}
	return id
}

TRIANGLE_STEP :: math.TAU / 3

make_a_triangle :: proc(center: [2]f32, angle: f32, radius: f32) -> (a, b, c: [2]f32) {
	a = center + {math.cos(angle), math.sin(angle)} * radius
	b = center + {math.cos(angle - TRIANGLE_STEP), math.sin(angle - TRIANGLE_STEP)} * radius
	c = center + {math.cos(angle + TRIANGLE_STEP), math.sin(angle + TRIANGLE_STEP)} * radius
	return
}

display_hsv_wheel :: proc(self: ^HSV_Wheel) {

	handle_object_click(self, sticky = true)

	size := min(box_width(self.box), box_height(self.box))
	outer_radius := size / 2
	inner_radius := outer_radius * 0.75

	center := box_center(self.box)
	angle := self.value.x * math.RAD_PER_DEG

	delta_to_mouse := global_state.mouse_pos - center
	distance_to_mouse := linalg.length(delta_to_mouse)

	if distance_to_mouse <= outer_radius {
		hover_object(self)
	}

	if .Pressed in new_state(self.state) {
		if distance_to_mouse > inner_radius {
			self.state.current += {.Active}
		}
	}
	if .Pressed in self.state.current {
		if .Active in self.state.current {
			self.value.x = math.atan2(delta_to_mouse.y, delta_to_mouse.x) / math.RAD_PER_DEG
			if self.value.x < 0 {
				self.value.x += 360
			}
		} else {
			point := global_state.mouse_pos
			point_a, point_b, point_c := make_a_triangle(center, angle, inner_radius)
			if !triangle_contains_point(point_a, point_b, point_c, point) {
				point = triangle_closest_point(point_a, point_b, point_c, point)
			}
			u, v, w := triangle_barycentric(point_a, point_b, point_c, point)
			self.value.z = clamp(1 - v, 0, 1)
			self.value.y = clamp(u / self.value.z, 0, 1)
		}
		self.state.current += {.Changed}
	} else {
		self.state.current -= {.Active}
	}

	if object_is_visible(self) {
		vgo.stroke_circle(
			center,
			outer_radius,
			width = (outer_radius - inner_radius),
			paint = vgo.make_wheel_gradient(center),
		)

		point_a, point_b, point_c := make_a_triangle(
			center,
			self.value.x * math.RAD_PER_DEG,
			inner_radius,
		)

		vgo.fill_polygon(
			{point_a, point_b, point_c},
			paint = vgo.make_tri_gradient(
				{point_a, point_b, point_c},
				{vgo.color_from_hsva({self.value.x, 1, 1, 1}), vgo.BLACK, vgo.WHITE},
			),
		)

		point := linalg.lerp(
			linalg.lerp(point_c, point_a, clamp(self.value.y, 0, 1)),
			point_b,
			clamp(1 - self.value.z, 0, 1),
		)
		r: f32 = 9 if (self.state.current >= {.Pressed} && .Active not_in self.state.current) else 7
		vgo.fill_circle(point, r + 1, paint = vgo.BLACK if self.value.z > 0.5 else vgo.WHITE)
		vgo.fill_circle(
			point,
			r,
			paint = vgo.color_from_hsva({self.value.x, self.value.y, self.value.z, 1}),
		)
	}
}
