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
	open_time: f32,
	hsva:      [4]f32,
}

color_picker :: proc(value: ^vgo.Color, show_hex: bool = false, show_alpha: bool = true, loc := #caller_location) {
	if value == nil {
		return
	}
	object := get_object(hash(loc))
	text_layout: vgo.Text_Layout
	if show_hex {
		text_layout := vgo.make_text_layout(
			fmt.tprintf("#%6x", vgo.hex_from_color(value^)),
			global_state.style.default_text_size,
			global_state.style.monospace_font,
		)
		object.size = text_layout.size + global_state.style.text_padding * 2
	}
	if object.variant == nil {
		object.variant = Color_Picker{}
	}
	object.box = next_box(object.size)
	object.state.input_mask = OBJECT_STATE_ALL
	if begin_object(object) {
		defer end_object()

		extras := &object.variant.(Color_Picker)


		object.hover_time = animate(object.hover_time, 0.1, .Hovered in object.state.current)
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
			accent_color := vgo.Black if max(vgo.luminance_of(value^), 1 - f32(value.a) / 255) > 0.45 else vgo.White
			vgo.push_scissor(vgo.make_box(object.box, current_options().radius))
			draw_checkerboard_pattern(
				object.box,
				box_height(object.box) / 2,
				vgo.blend(style().color.checkers0, value^, vgo.White),
				vgo.blend(style().color.checkers1, value^, vgo.White),
			)
			if show_hex {
				vgo.fill_text_layout(
					text_layout,
					box_center(object.box),
					align = 0.5,
					paint = accent_color,
				)
			}
			vgo.pop_scissor()
		}

		PADDING :: 10
		if .Open in object.state.current {
			if .Open not_in object.state.previous {
				extras.hsva = vgo.hsva_from_color(value^)
			}

			push_id(object.id)
			defer pop_id()

			if begin_layer(.Back, options = {.In_Front_Of_Parent}) {
				defer end_layer()

				baseline := box_center_y(object.box)
				set_next_box(
					{{object.box.hi.x, baseline - 100}, {object.box.hi.x + 200, baseline + 100}},
				)
				if begin_layout(side = .Left) {
					defer end_layout()
					push_options({})
					defer pop_options()

					set_rounded_corners(ALL_CORNERS)
					foreground()
					vgo.stroke_box(current_box(), 1, current_options().radius, paint = style().color.button)
					shrink(10)
					alpha_slider(&extras.hsva.w)
					space(10)
					hsv_wheel((^[3]f32)(&extras.hsva))
					space(10)
					// todo figure out how to do row placement
					nearest := vgo.find_nearest_color(vgo.color_from_hsva(extras.hsva))
					label(
						nearest.name,
						color = nearest.color,
					)
				}

				if object_was_just_changed(object) {
					value^ = vgo.color_from_hsva(extras.hsva)
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
	color: vgo.Color = vgo.Black,
	axis: Axis = .Y,
	loc := #caller_location,
) {
	if value == nil {
		return
	}
	color := color
	object := get_object(hash(loc))
	object.size = global_state.style.visual_size
	if axis == .Y {
		object.size.xy = object.size.yx
	}
	object.box = next_box(object.size)
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
				style().color.checkers0,
				style().color.checkers1,
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
					paint = style().color.content,
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
	object.box = next_box(object.size)
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
					{vgo.color_from_hsva({value.x, 1, 1, 1}), vgo.Black, vgo.White},
				),
			)

			point := linalg.lerp(
				linalg.lerp(point_c, point_a, clamp(value.y, 0, 1)),
				point_b,
				clamp(1 - value.z, 0, 1),
			)
			r: f32 =
				9 if (object.state.current >= {.Pressed} && .Active not_in object.state.current) else 7
			vgo.fill_circle(point, r + 1, paint = vgo.Black if value.z > 0.5 else vgo.White)
			vgo.fill_circle(point, r, paint = vgo.color_from_hsva({value.x, value.y, value.z, 1}))
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
