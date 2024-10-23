package onyx
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

draw_checkerboard_pattern :: proc(box: Box, size: [2]f32, primary, secondary: Color) {
	draw_box_fill(box, primary)
	for x in 0 ..< int(math.ceil(box_width(box) / size.x)) {
		for y in 0 ..< int(math.ceil(box_height(box) / size.y)) {
			if (x + y) % 2 == 0 {
				pos := box.lo + [2]f32{f32(x), f32(y)} * size
				draw_box_fill({pos, linalg.min(pos + size, box.hi)}, secondary)
			}
		}
	}
}

Color_Conversion_Widget_Kind :: struct {
	// This value is used as a mediary while the value is being edited
	hsva:   [4]f32,
	inputs: [Color_Format]strings.Builder,
}

Color_Format :: enum {
	HEX,
	RGB,
	CMYK,
	HSL,
}
Color_Format_Set :: bit_set[Color_Format]

Color_Button_Info :: struct {
	using _:       Widget_Info,
	value:         ^Color,
	show_alpha:    bool,
	input_formats: Color_Format_Set,
	text_job:      Text_Job,
	changed:       bool,
}

init_color_button :: proc(using info: ^Color_Button_Info, loc := #caller_location) -> bool {
	if value == nil do return false
	text_job = make_text_job(
		{
			text = fmt.tprintf("%6x", hex_from_color(value^)),
			font = core.style.monospace_font,
			size = 20,
			align_h = .Middle,
			align_v = .Middle,
		},
	) or_return
	id = hash(loc)
	self = get_widget(id) or_return
	desired_size = core.style.visual_size
	in_state_mask = Widget_State{}
	return true
}

add_color_button :: proc(using info: ^Color_Button_Info) -> bool {
	begin_widget(info) or_return
	defer end_widget()

	menu_behavior(self)

	if self.visible {
		draw_rounded_box_shadow(
			self.box,
			core.style.rounding,
			6,
			fade({0, 0, 0, 40}, max(self.hover_time, self.open_time)),
		)
		draw_rounded_box_fill(self.box, core.style.rounding, value^)
		set_scissor_shape(add_shape_box(self.box, core.style.rounding))
		draw_text_glyphs(
			text_job,
			box_center(self.box),
			{0, 0, 0, 255} if get_color_brightness(value^) > 0.45 else 255,
		)
		set_scissor_shape(0)
		draw_rounded_box_stroke(
			self.box,
			core.style.rounding,
			2,
			fade(core.style.color.accent, max(self.hover_time, self.open_time)),
		)
	}

	kind := widget_kind(self, Color_Conversion_Widget_Kind)
	PADDING :: 10
	if .Open in self.state {
		if .Open not_in self.last_state {
			kind.hsva = hsva_from_color(value^)
		}

		// Salt the hash stack to avoid collisions with other color pickers
		push_id(hash(uintptr(value)))
		defer pop_id()

		picker_info := HSVA_Picker_Info {
			hsva = &kind.hsva,
			mode = .Wheel,
		}
		init_hsva_picker(&picker_info)

		layer_size := picker_info.desired_size + PADDING * 2
		input_size: [2]f32

		slider_info := Alpha_Slider_Info {
			value    = &kind.hsva.a,
			vertical = true,
		}

		if show_alpha {
			init_alpha_slider(&slider_info)
		}

		inputs: [Color_Format]Input_Info

		for format, f in Color_Format {
			if format in input_formats {
				inputs[format].monospace = true
				inputs[format].builder = &kind.inputs[format]
				text: string
				switch format {
				case .HEX:
					text = fmt.tprintf("#%6x", hex_from_color(value^))
				case .RGB:
					text = fmt.tprintf("%i, %i, %i", value.r, value.g, value.b)
				case .CMYK:
				case .HSL:
					hsl := hsl_from_norm_rgb(normalize_color(value^).rgb)
					text = fmt.tprintf("%.0f, %.0f, %.0f", hsl.x, hsl.y * 100, hsl.z * 100)
				}
				// inputs[format].prefix = fmt.tprintf("%v ", format)
				if strings.builder_len(inputs[format].builder^) == 0 {
					strings.write_string(inputs[format].builder, text)
				}
				push_id(f + 1)
				init_input(&inputs[format])
				pop_id()
				input_size.x = max(input_size.x, inputs[format].desired_size.x)
			}
		}

		menu_layer := get_popup_layer_info(self, layer_size + input_size, side = .Right)
		if layer(&menu_layer) {
			draw_shadow(layout_box(), self.open_time)
			foreground()
			defer {
				draw_rounded_box_fill(
					current_layer().?.box,
					core.style.rounding,
					fade(core.style.color.foreground, 1 - self.open_time),
				)
			}

			shrink_layout(PADDING)

			set_height_auto()
			set_width_auto()
			set_side(.Left)
			add_hsva_picker(&picker_info)
			add_space(10)
			add_alpha_slider(&slider_info)
			add_space(10)
			set_side(.Top)
			for format, f in Color_Format {
				if format not_in input_formats do continue
				if f > 0 {
					add_space(10)
				}
				label({id = hash(f + 1), text = fmt.tprint(format)})
				add_input(&inputs[format])
				// Detect change and update the value
				if inputs[format].changed {
					#partial switch format {
					case .RGB:
						if color, ok := parse_rgba(inputs[format].text_info.text); ok {
							kind.hsva.xyz = hsva_from_color(color).xyz
						}
					case .HEX:
						if hex, ok := strconv.parse_u64_of_base(inputs[format].text_info.text[1:], 16); ok {
							kind.hsva.xyz = hsva_from_color(color_from_hex(u32(hex))).xyz
							changed = true
						}
					}
					value^ = color_from_hsva(kind.hsva)
				}
			}

			// Apply changes from wheel and slider
			if picker_info.changed || slider_info.changed {
				value^ = color_from_hsva(kind.hsva)
				changed = true
			}

			// If the value was changed anywhere, clear all the inputs so they get reformatted next frame
			if changed {
				for format in Color_Format {
					if format in input_formats && !inputs[format].changed {
						strings.builder_reset(inputs[format].builder)
					}
				}
			}

			// If the layer is not focused or hovered and the widget loses focus: close the dialog
			if menu_layer.self.state & {.Hovered, .Focused} == {} && .Focused not_in self.state {
				self.state -= {.Open}
			}
		}
	}

	return true
}

color_button :: proc(info: Color_Button_Info, loc := #caller_location) -> Color_Button_Info {
	info := info
	if init_color_button(&info, loc) {
		add_color_button(&info)
	}
	return info
}

Alpha_Slider_Info :: struct {
	using _:  Widget_Info,
	value:    ^f32,
	vertical: bool,
	changed:  bool,
	color:    Color,
}

init_alpha_slider :: proc(using info: ^Alpha_Slider_Info, loc := #caller_location) -> bool {
	if value == nil do return false
	desired_size = core.style.visual_size
	if vertical {
		desired_size.xy = desired_size.yx
	}
	sticky = true
	id = hash(loc)
	self = get_widget(id) or_return
	return true
}

add_alpha_slider :: proc(using info: ^Alpha_Slider_Info) -> bool {
	begin_widget(info) or_return
	defer end_widget()

	i := int(info.vertical)
	j := 1 - i

	if .Pressed in self.state {
		value^ = clamp(
			(core.mouse_pos[i] - self.box.lo[i]) / (self.box.hi[i] - self.box.lo[i]),
			0,
			1,
		)
		changed = true
	}

	if self.visible {
		R :: 4
		box := self.box
		// box.lo[j] += R * 1.5
		// box.hi[j] -= R * 1.5
		draw_checkerboard_pattern(
			box,
			(box.hi[j] - box.lo[j]) / 2,
			{210, 210, 210, 255},
			{160, 160, 160, 255},
		)
		color.a = 255
		time := clamp(value^, 0, 1)
		pos := box.lo[i] + (box.hi[i] - box.lo[i]) * time
		if vertical {
			draw_vertical_box_gradient(box, fade(color, 0), color)
			draw_box_fill({{box.lo.x, pos - 1}, {box.hi.x, pos + 1}}, core.style.color.content)
			// draw_triangle_fill(
			// 	{box.lo.x - 1.5 * R, pos - 0.866025 * R},
			// 	{box.lo.x, pos},
			// 	{box.lo.x - 1.5 * R, pos + 0.866025 * R},
			// 	core.style.color.content,
			// )
			// draw_triangle_fill(
			// 	{box.hi.x + 1.5 * R, pos - 0.866025 * R},
			// 	{box.hi.x, pos},
			// 	{box.hi.x + 1.5 * R, pos + 0.866025 * R},
			// 	core.style.color.content,
			// )
		} else {
			draw_horizontal_box_gradient(box, fade(color, 0), color)
			draw_triangle_fill(
				{pos - 0.866025 * R, box.lo.y - 1.5 * R},
				{pos, box.lo.y},
				{pos + 0.866025 * R, box.lo.y - 1.5 * R},
				core.style.color.content,
			)
			draw_triangle_fill(
				{pos - 0.866025 * R, box.hi.y + 1.5 * R},
				{pos, box.hi.y},
				{pos + 0.866025 * R, box.hi.y + 1.5 * R},
				core.style.color.content,
			)
		}
	}

	if point_in_box(core.mouse_pos, self.box) {
		hover_widget(self)
	}

	return true
}

alpha_slider :: proc(info: Alpha_Slider_Info, loc := #caller_location) -> Alpha_Slider_Info {
	info := info
	if init_alpha_slider(&info, loc) {
		add_alpha_slider(&info)
	}
	return info
}

HSVA_Picker_Mode :: enum {
	Square,
	Wheel,
}

HSVA_Picker_Info :: struct {
	using _: Widget_Info,
	hsva:    ^[4]f32,
	mode:    HSVA_Picker_Mode,
	changed: bool,
}

init_hsva_picker :: proc(using info: ^HSVA_Picker_Info) -> bool {
	if info == nil do return false
	if info.hsva == nil do return false
	desired_size = 200
	fixed_size = true
	sticky = true
	id = hash(uintptr(hsva))
	self = get_widget(id) or_return
	return true
}

add_hsva_picker :: proc(using info: ^HSVA_Picker_Info) -> bool {
	begin_widget(info) or_return
	defer end_widget()

	size := min(box_width(self.box), box_height(self.box))
	outer := size / 2
	inner := outer * 0.75

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
	}
	if .Pressed in self.state {
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
			hsva.z = clamp(1 - v, 0, 1)
			hsva.y = clamp(u / hsva.z, 0, 1)
		}
		changed = true
	} else {
		self.state -= {.Active}
	}

	if self.visible {
		// H wheel
		STEP :: math.TAU / 48.0
		wheel_shape := add_shape(
			Shape {
				kind = .Circle,
				cv0 = center,
				stroke = true,
				width = (outer - inner) - 4,
				radius = (inner + outer) * 0.5,
			},
		)
		for t: f32 = 0; t < math.TAU; t += STEP {
			normal := [2]f32{math.cos(t), math.sin(t)}
			next_normal := [2]f32{math.cos(t + STEP), math.sin(t + STEP)}

			inner_radius := inner - 2
			outer_radius := outer + 2

			col0 := color_from_hsva({t * math.DEG_PER_RAD, 1, 1, 1})
			col1 := color_from_hsva({(t + STEP) * math.DEG_PER_RAD, 1, 1, 1})

			a := add_vertex(
				{pos = center + normal * outer_radius, col = col0, shape = wheel_shape},
			)
			b := add_vertex(
				{pos = center + normal * inner_radius, col = col0, shape = wheel_shape},
			)
			c := add_vertex(
				{pos = center + next_normal * inner_radius, col = col1, shape = wheel_shape},
			)
			d := add_vertex(
				{pos = center + next_normal * outer_radius, col = col1, shape = wheel_shape},
			)

			add_indices(a, b, c, a, c, d)
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
		tri_shape := add_polygon_shape(point_a, point_b, point_c)
		a := add_vertex(
			{
				pos = center + {math.cos(angle), math.sin(angle)} * (inner + 2),
				col = color_from_hsva({hsva.x, 1, 1, 1}),
				shape = tri_shape,
			},
		)
		b := add_vertex(
			{
				pos = center +
				{math.cos(angle - TRIANGLE_STEP), math.sin(angle - TRIANGLE_STEP)} * (inner + 2),
				col = {0, 0, 0, 255},
				shape = tri_shape,
			},
		)
		c := add_vertex(
			{
				pos = center +
				{math.cos(angle + TRIANGLE_STEP), math.sin(angle + TRIANGLE_STEP)} * (inner + 2),
				col = 255,
				shape = tri_shape,
			},
		)
		add_indices(a, b, c)

		// SV circle
		point := linalg.lerp(
			linalg.lerp(point_c, point_a, clamp(hsva.y, 0, 1)),
			point_b,
			clamp(1 - hsva.z, 0, 1),
		)
		r: f32 = 9 if (self.state >= {.Pressed} && .Active not_in self.state) else 7
		draw_circle_fill(point, r + 1, {0, 0, 0, 255} if hsva.z > 0.5 else 255)
		draw_circle_fill(point, r, color_from_hsva({hsva.x, hsva.y, hsva.z, 1}))
	}

	return true
}

hsva_picker :: proc(info: HSVA_Picker_Info, loc := #caller_location) -> HSVA_Picker_Info {
	info := info
	info.id = hash(loc)
	if init_hsva_picker(&info) {
		add_hsva_picker(&info)
	}
	return info
}

Color_Picker_Info :: struct {
	using _: Widget_Info,
	color:   ^Color,
}

init_color_picker :: proc(using info: ^Color_Picker_Info, loc := #caller_location) -> bool {
	if info.color == nil do return false
	if id == 0 do id = hash(loc)
	self = get_widget(id) or_return
	return true
}

add_color_picker :: proc(using info: ^Color_Picker_Info) -> bool {
	begin_widget(info) or_return
	defer end_widget()

	if self.visible {
		draw_box_fill(self.box, color^)
		draw_box_stroke(self.box, 1, core.style.color.substance)
	}

	return true
}
