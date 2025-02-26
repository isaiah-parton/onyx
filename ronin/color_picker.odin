package ronin

import kn "local:katana"
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

draw_checkerboard_pattern :: proc(box: Box, size: [2]f32, primary, secondary: kn.Color) {
	kn.add_box(box, paint = primary)
	for x in 0 ..< int(math.ceil(box_width(box) / size.x)) {
		for y in 0 ..< int(math.ceil(box_height(box) / size.y)) {
			if (x + y) % 2 == 0 {
				pos := box.lo + [2]f32{f32(x), f32(y)} * size
				kn.add_box({pos, linalg.min(pos + size, box.hi)}, paint = secondary)
			}
		}
	}
}

Color_Picker :: struct {
	open_time: f32,
	hsva:      [4]f32,
}

color_picker :: proc(value: ^kn.Color, show_hex: bool = false, show_alpha: bool = true, loc := #caller_location) {
	if value == nil {
		return
	}
	object := get_object(hash(loc))
	text_layout: kn.Text
	if show_hex {
		text_layout := kn.make_text(
			fmt.tprintf("#%6x", kn.hex_from_color(value^)),
			global_state.style.default_text_size,
			global_state.style.monospace_font,
		)
		object.size = text_layout.size + global_state.style.text_padding * 2
	}
	if object.variant == nil {
		object.variant = Color_Picker{}
	}
	object.state.input_mask = OBJECT_STATE_ALL
	if begin_object(object) {
		defer end_object()

		extras := &object.variant.(Color_Picker)


		object.animation.hover = animate(object.animation.hover, 0.1, .Hovered in object.state.current)
		if .Open in object.state.current {
			extras.open_time = animate(extras.open_time, 0.3, true)
		} else {
			extras.open_time = 0
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
			accent_color := kn.Black if max(kn.luminance_of(value^), 1 - f32(value.a) / 255) > 0.45 else kn.White
			kn.push_scissor(kn.make_box(object.box, get_current_options().radius))
			draw_checkerboard_pattern(
				object.box,
				box_height(object.box) / 2,
				kn.blend(get_current_style().color.checkers0, value^, kn.White),
				kn.blend(get_current_style().color.checkers1, value^, kn.White),
			)
			if show_hex {
				kn.add_text(
					text_layout,
					box_center(object.box) - text_layout.size * 0.5,
					paint = accent_color,
				)
			}
			kn.pop_scissor()
		}

		PADDING :: 10
		if .Open in object.state.current {
			if .Open not_in object.state.previous {
				extras.hsva = kn.hsva_from_color(value^)
			}

			push_id(object.id)
			defer pop_id()

			if begin_layer(.Back, options = {.In_Front_Of_Parent}) {
				defer end_layer()

				baseline := box_center_y(object.box)
				set_next_box(
					{{object.box.hi.x, baseline - 100}, {object.box.hi.x + 200, baseline + 100}},
				)
				if do_layout(as_row) {
					push_options({})
					defer pop_options()

					set_rounded_corners(ALL_CORNERS)
					foreground()
					kn.add_box_lines(get_current_layout().box, 1, get_current_options().radius, paint = get_current_style().color.button)
					shrink(10)
					alpha_slider(&extras.hsva.w)
					space()
					hsv_wheel((^[3]f32)(&extras.hsva))
				}

				if object_was_just_changed(object) {
					value^ = kn.color_from_hsva(extras.hsva)
					object.state.current += {.Changed}
				}

				if .Focused not_in current_layer().?.state &&
				   .Focused not_in object.state.current {
					object.state.current -= {.Open}
				}
			}
		}
	}
}

alpha_slider :: proc(
	value: ^f32,
	color: kn.Color = kn.Black,
	axis: Axis = .Y,
	loc := #caller_location,
) {
	if value == nil {
		return
	}
	color := color
	object := get_object(hash(loc))
	object.size = global_state.style.scale
	if axis == .Y {
		object.size.xy = object.size.yx
	}
	if begin_object(object) {
		defer end_object()



		i := int(axis)
		j := 1 - i

		if .Pressed in object.state.current {
			value^ = clamp(
				(global_state.mouse_pos[i] - object.box.lo[i]) /
				(object.box.hi[i] - object.box.lo[i]),
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
				get_current_style().color.checkers0,
				get_current_style().color.checkers1,
			)
			color.a = 255
			time := clamp(value^, 0, 1)
			pos := box.lo[i] + (box.hi[i] - box.lo[i] - 4) * time
			if axis == .Y {
				kn.add_box(
					box,
					paint = kn.make_linear_gradient(
						box.lo,
						{box.lo.x, box.hi.y},
						kn.fade(color, 0.0),
						color,
					),
				)
				kn.add_box_lines(
					{{box.lo.x, pos}, {box.hi.x, pos + 4}},
					1,
					paint = get_current_style().color.content,
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
	object := get_object(hash(loc))
	object.size = 200
	if begin_object(object) {
		defer end_object()



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
			kn.add_circle_lines(
				center,
				outer_radius,
				width = (outer_radius - inner_radius),
				paint = kn.make_wheel_gradient(center),
			)

			point_a, point_b, point_c := make_a_triangle(
				center,
				value.x * math.RAD_PER_DEG,
				inner_radius,
			)

			kn.add_polygon(
				{point_a, point_b, point_c},
				paint = kn.make_tri_gradient(
					{point_a, point_b, point_c},
					{kn.color_from_hsva({value.x, 1, 1, 1}), kn.Black, kn.White},
				),
			)

			point := linalg.lerp(
				linalg.lerp(point_c, point_a, clamp(value.y, 0, 1)),
				point_b,
				clamp(1 - value.z, 0, 1),
			)
			r: f32 =
				9 if (object.state.current >= {.Pressed} && .Active not_in object.state.current) else 7
			kn.add_circle(point, r + 1, paint = kn.Black if value.z > 0.5 else kn.White)
			kn.add_circle(point, r, paint = kn.color_from_hsva({value.x, value.y, value.z, 1}))
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
