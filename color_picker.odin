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
	value:        ^vgo.Color,
	open_time:    f32,
}

color_picker :: proc(value: ^vgo.Color, show_alpha: bool = true, loc := #caller_location) {
	object := persistent_object(hash(loc))
	if begin_object(object) {
		defer end_object()

		object.desired_size = global_state.style.visual_size * {0.5, 1}

		if object.variant == nil {
			object.variant = Color_Picker {
				object = object,
			}
		}
		variant := &object.variant.(Color_Picker)
		variant.value = value
	}
}

display_color_picker :: proc(self: ^Color_Picker) {
	if self.value == nil do return

	handle_object_click(self)
	if .Open in self.state {
		self.open_time = animate(self.open_time, 0.3, true)
	} else {
		self.open_time = 0
	}
	if .Pressed in (self.state - self.last_state) {
		self.state += {.Open}
	}
	if .Hovered in self.state {
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
			vgo.blend(global_state.style.color.checker_bg[0], self.value^, vgo.WHITE),
			vgo.blend(global_state.style.color.checker_bg[1], self.value^, vgo.WHITE),
		)
		vgo.fill_text(
			fmt.tprintf("#%6x", vgo.hex_from_color(self.value^)),
			global_state.style.default_text_size,
			box_center(self.box),
			align_x = .Center,
			align_y = .Center,
			paint = vgo.BLACK if max(vgo.luminance_of(self.value^), 1 - f32(self.value.a) / 255) > 0.45 else vgo.WHITE,
		)
		vgo.pop_scissor()
	}

	PADDING :: 10
	if .Open in self.state {
		if .Open not_in self.last_state {
			self.hsva = vgo.hsva_from_color(self.value^)
		}

		push_id(hash(uintptr(self.value)))
		defer pop_id()

		if begin_layout(
			axis = .X,
			placement = Future_Box_Placement{origin = self.box.hi},
			padding = global_state.style.menu_padding,
		) {
			defer end_layout()

			alpha_slider(&self.hsva.w)
			hsv := self.hsva.xyz
			hsv_wheel(&hsv)
		}
	}
}

Alpha_Slider :: struct {
	using object: ^Object,
	value:        ^f32,
	axis:         Axis,
	color:        vgo.Color,
}

alpha_slider :: proc(
	value: ^f32,
	color: vgo.Color = vgo.BLACK,
	axis: Axis = .Y,
	loc := #caller_location,
) {
	if value == nil do return
	object := persistent_object(hash(loc))
	if begin_object(object) {
		defer end_object()

		if object.variant == nil {
			object.variant = Alpha_Slider {
				object = object,
				value  = value,
			}
		}
		slider := &object.variant.(Alpha_Slider)
		slider.axis = axis
		slider.color = color
		slider.desired_size = global_state.style.visual_size
		if slider.axis == .Y {
			slider.desired_size.xy = slider.desired_size.yx
		}
	}
}

display_alpha_slider :: proc(self: ^Alpha_Slider) {

	i := int(self.axis)
	j := 1 - i

	if .Pressed in self.state {
		self.value^ = clamp(
			(global_state.mouse_pos[i] - self.box.lo[i]) / (self.box.hi[i] - self.box.lo[i]),
			0,
			1,
		)
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
		time := clamp(self.value^, 0, 1)
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
	hsv:          ^[3]f32,
}

hsv_wheel :: proc(hsv: ^[3]f32, loc := #caller_location) {
	object := persistent_object(hash(loc))
	if begin_object(object) {
		defer end_object()

		if object.variant == nil {
			object.variant = HSV_Wheel {
				object = object,
			}
		}
		hsva_wheel := &object.variant.(HSV_Wheel)
		hsva_wheel.hsv = hsv
		hsva_wheel.desired_size = 200
	}
}

TRIANGLE_STEP :: math.TAU / 3

make_a_triangle :: proc(center: [2]f32, angle: f32, radius: f32) -> (a, b, c: [2]f32) {
	a = center + {math.cos(angle), math.sin(angle)} * radius
	b = center + {math.cos(angle - TRIANGLE_STEP), math.sin(angle - TRIANGLE_STEP)} * radius
	c = center + {math.cos(angle + TRIANGLE_STEP), math.sin(angle + TRIANGLE_STEP)} * radius
	return
}

display_hsv_wheel :: proc(object: ^HSV_Wheel) {
	handle_object_click(object, sticky = true)

	size := min(box_width(object.box), box_height(object.box))
	outer_radius := size / 2
	inner_radius := outer_radius * 0.75

	center := box_center(object.box)
	angle := object.hsv.x * math.RAD_PER_DEG

	point_a, point_b, point_c := make_a_triangle(center, angle, inner_radius)

	delta_to_mouse := global_state.mouse_pos - center
	distance_to_mouse := linalg.length(delta_to_mouse)

	if distance_to_mouse <= outer_radius {
		hover_object(object)
	}

	if .Pressed in (object.state - object.last_state) {
		if distance_to_mouse > inner_radius {
			object.state += {.Active}
		}
	}
	if .Pressed in object.state {
		if .Active in object.state {
			object.hsv.x = math.atan2(delta_to_mouse.y, delta_to_mouse.x) / math.RAD_PER_DEG
			if object.hsv.x < 0 {
				object.hsv.x += 360
			}
		} else {
			point := global_state.mouse_pos
			if !triangle_contains_point(point_a, point_b, point_c, point) {
				point = triangle_closest_point(point_a, point_b, point_c, point)
			}
			u, v, w := triangle_barycentric(point_a, point_b, point_c, point)
			object.hsv.z = clamp(1 - v, 0, 1)
			object.hsv.y = clamp(u / object.hsv.z, 0, 1)
		}
	} else {
		object.state -= {.Active}
	}

	if object_is_visible(object) {
		vgo.stroke_circle(
			center,
			outer_radius,
			width = (outer_radius - inner_radius),
			paint = vgo.make_wheel_gradient(center),
		)

		point_a, point_b, point_c := make_a_triangle(
			center,
			object.hsv.x * math.RAD_PER_DEG,
			inner_radius,
		)

		vgo.fill_polygon(
			{point_a, point_b, point_c},
			paint = vgo.make_tri_gradient(
				{point_a, point_b, point_c},
				{vgo.color_from_hsva({object.hsv.x, 1, 1, 1}), vgo.BLACK, vgo.WHITE},
			),
		)

		point := linalg.lerp(
			linalg.lerp(point_c, point_a, clamp(object.hsv.y, 0, 1)),
			point_b,
			clamp(1 - object.hsv.z, 0, 1),
		)
		r: f32 = 9 if (object.state >= {.Pressed} && .Active not_in object.state) else 7
		vgo.fill_circle(point, r + 1, paint = vgo.BLACK if object.hsv.z > 0.5 else vgo.WHITE)
		vgo.fill_circle(
			point,
			r,
			paint = vgo.color_from_hsva({object.hsv.x, object.hsv.y, object.hsv.z, 1}),
		)
	}
}