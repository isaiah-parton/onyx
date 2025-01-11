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

nearest_point_on_line :: proc(a, b, p: [2]f32) -> [2]f32 {
	ap := p - a
	ab_dir := b - a
	dot := ap.x * ab_dir.x + ap.y * ab_dir.y
	if dot < 0 do return a
	ab_len_sqr := ab_dir.x * ab_dir.x + ab_dir.y * ab_dir.y
	if dot > ab_len_sqr do return b
	return a + ab_dir * dot / ab_len_sqr
}

nearest_point_in_triangle :: proc(a, b, c, p: [2]f32) -> [2]f32 {
	proj_ab := nearest_point_on_line(a, b, p)
	proj_bc := nearest_point_on_line(b, c, p)
	proj_ca := nearest_point_on_line(c, a, p)
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
	object.size = global_state.style.visual_size * {0.5, 1}
	if object.variant == nil {
		object.variant = Color_Picker {
			object = object,
		}
	}
	if begin_object(object) {
		defer end_object()

		object := &object.variant.(Color_Picker)
		if .Changed in object.state.previous {
			value^ = object.value
			draw_frames(1)
		} else {
			object.value = value^
		}
	}
	return id
}

display_color_picker :: proc(object: ^Color_Picker) {

	handle_object_click(object)

	if .Open in object.state.current {
	object.open_time = animate(object.open_time, 0.3, true)
	} else {
		object.open_time = 0
	}
	if .Pressed in new_state(object.state) {
		object.state.current += {.Open}
	}
	if .Hovered in object.state.current {
		global_state.cursor_type = .Pointing_Hand
	}
	if point_in_box(global_state.mouse_pos, object.box) {
		hover_object(object)
	}

	if object_is_visible(object) {
		shadow_opacity := object.open_time
		if shadow_opacity > 0 {
			vgo.box_shadow(
				object.box,
				global_state.style.rounding,
				6,
				vgo.fade(global_state.style.color.shadow, shadow_opacity),
			)
		}

		checker_box := shrink_box(object.box, 1)
		vgo.push_scissor(vgo.make_box(checker_box, box_height(checker_box) / 2))
		draw_checkerboard_pattern(
			object.box,
			box_height(object.box) / 2,
			vgo.blend(global_state.style.color.checker_bg[0], object.value, vgo.WHITE),
			vgo.blend(global_state.style.color.checker_bg[1], object.value, vgo.WHITE),
		)
		vgo.fill_text(
			fmt.tprintf("#%6x", vgo.hex_from_color(object.value)),
			global_state.style.default_text_size,
			box_center(object.box),
			align = 0.5,
			paint = vgo.BLACK if max(vgo.luminance_of(object.value), 1 - f32(object.value.a) / 255) > 0.45 else vgo.WHITE,
		)
		vgo.pop_scissor()
	}

	PADDING :: 10
	if .Open in object.state.current {
		if .Open not_in object.state.previous {
		object.hsva = vgo.hsva_from_color(object.value)
		}

		push_id(object.id)
		defer pop_id()

		if begin_layer(options = {.Attached}, kind = .Background) {
			defer end_layer()

			if begin_layout(side = .Left) {
				defer end_layout()

				shrink(10)

				foreground()
				alpha_slider(&object.hsva.w)
				space(10)
				hsv_wheel((^[3]f32)(&object.hsva))
			}

			if object_was_just_changed(last_object().?) {
				object.value = vgo.color_from_hsva(object.hsva)
				object.state.current += {.Changed}
			}

			if .Focused not_in current_layer().?.state && .Focused not_in object.state.current {
				object.state.current -= {.Open}
			}
		}
	}
}

alpha_slider :: proc(
	value: ^f32,
	color: vgo.Color = vgo.BLACK,
	axis: Axis = .Y,
	loc := #caller_location,
) {
	if value == nil {
		return
	}
	color := color
	object := persistent_object(hash(loc))
	object.size = global_state.style.visual_size
	if axis == .Y {
		object.size.xy = object.size.yx
	}
	if begin_object(object) {
		defer end_object()

		handle_object_click(object, true)

		i := int(axis)
		j := 1 - i

		if .Pressed in object.state.current {
			value^ = clamp(
				(global_state.mouse_pos[i] - object.box.lo[i]) / (object.box.hi[i] - object.box.lo[i]),
				0,
				1,
			)
			object.state.current += {.Changed}
		}

		if object_is_visible(object) {
			R :: 4
			box := object.box
			draw_checkerboard_pattern(
				box,
				(box.hi[j] - box.lo[j]) / 2,
				global_state.style.color.checker_bg[0],
				global_state.style.color.checker_bg[1],
			)
			color.a = 255
			time := clamp(value^, 0, 1)
			pos := box.lo[i] + (box.hi[i] - box.lo[i] - 4) * time
			if axis == .Y {
				vgo.fill_box(
					box,
					paint = vgo.make_linear_gradient(
						box.lo,
						{box.lo.x, box.hi.y},
						vgo.fade(color, 0.0),
						color,
					),
				)
				vgo.stroke_box(
					{{box.lo.x, pos}, {box.hi.x, pos + 4}},
					1,
					paint = global_state.style.color.content,
				)
			}
		}

		if point_in_box(global_state.mouse_pos, object.box) {
			hover_object(object)
		}
	}
	return
}

hsv_wheel :: proc(value: ^[3]f32, loc := #caller_location) {
	if value == nil {
		return
	}
	object := persistent_object(hash(loc))
	object.size = 200
	if begin_object(object) {
		defer end_object()

		handle_object_click(object, sticky = true)

		size := min(box_width(object.box), box_height(object.box))
		outer_radius := size / 2
		inner_radius := outer_radius * 0.75

		center := box_center(object.box)
		angle := value.x * math.RAD_PER_DEG

		delta_to_mouse := global_state.mouse_pos - center
		distance_to_mouse := linalg.length(delta_to_mouse)

		if distance_to_mouse <= outer_radius {
			hover_object(object)
		}

		if .Pressed in new_state(object.state) {
			if distance_to_mouse > inner_radius {
				object.state.current += {.Active}
			}
		}
		if .Pressed in object.state.current {
			if .Active in object.state.current {
				value.x = math.atan2(delta_to_mouse.y, delta_to_mouse.x) / math.RAD_PER_DEG
				if value.x < 0 {
					value.x += 360
				}
			} else {
				point := global_state.mouse_pos
				point_a, point_b, point_c := make_a_triangle(center, angle, inner_radius)
				if !triangle_contains_point(point_a, point_b, point_c, point) {
					point = nearest_point_in_triangle(point_a, point_b, point_c, point)
				}
				u, v, w := triangle_barycentric(point_a, point_b, point_c, point)
				value.z = clamp(1 - v, 0, 1)
				value.y = clamp(u / value.z, 0, 1)
			}
			object.state.current += {.Changed}
		} else {
			object.state.current -= {.Active}
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
				value.x * math.RAD_PER_DEG,
				inner_radius,
			)

			vgo.fill_polygon(
				{point_a, point_b, point_c},
				paint = vgo.make_tri_gradient(
					{point_a, point_b, point_c},
					{vgo.color_from_hsva({value.x, 1, 1, 1}), vgo.BLACK, vgo.WHITE},
				),
			)

			point := linalg.lerp(
				linalg.lerp(point_c, point_a, clamp(value.y, 0, 1)),
				point_b,
				clamp(1 - value.z, 0, 1),
			)
			r: f32 = 9 if (object.state.current >= {.Pressed} && .Active not_in object.state.current) else 7
			vgo.fill_circle(point, r + 1, paint = vgo.BLACK if value.z > 0.5 else vgo.WHITE)
			vgo.fill_circle(
				point,
				r,
				paint = vgo.color_from_hsva({value.x, value.y, value.z, 1}),
			)
		}
	}
	return
}

TRIANGLE_STEP :: math.TAU / 3

make_a_triangle :: proc(center: [2]f32, angle: f32, radius: f32) -> (a, b, c: [2]f32) {
	a = center + {math.cos(angle), math.sin(angle)} * radius
	b = center + {math.cos(angle - TRIANGLE_STEP), math.sin(angle - TRIANGLE_STEP)} * radius
	c = center + {math.cos(angle + TRIANGLE_STEP), math.sin(angle + TRIANGLE_STEP)} * radius
	return
}
