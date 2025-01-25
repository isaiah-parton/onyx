package onyx

import "../vgo"
import "base:intrinsics"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:strconv"
import "core:strings"

Slider :: struct {
	click_value: f64,
}

Slider_Result :: struct {
	using input_result: Input_Result,
}

object_was_clicked_in_place :: proc(object: ^Object) -> bool {
	return(
		.Pressed in (object.state.previous - object.state.current) &&
		mouse_point() == object.click.point \
	)
}

slider :: proc(
	value: ^$T,
	lower, upper: f64,
	lower_limit: f64 = 0,
	upper_limit: f64 = math.F64_MAX,
	format: string = "%.2f" when intrinsics.type_is_float(T) else "%i",
	loc := #caller_location,
) -> (
	result: Slider_Result,
) where intrinsics.type_is_numeric(T) {
	if value == nil {
		return
	}
	object := persistent_object(hash(loc))
	object.size = global_state.style.visual_size
	if object.variant == nil {
		object.variant = Slider{}
	}
	extras := &object.variant.(Slider)
	if begin_object(object) {
		defer end_object()

		object.box = next_box(object.size)

		if point_in_box(mouse_point(), object.box) {
			hover_object(object)
		}

		handle_object_click(object, true)

		if object_was_clicked_in_place(object) {
			focus_next_object()
		}

		if .Pressed in object.state.current {
			if .Pressed not_in object.state.previous {
				extras.click_value = f64(value^)
			}
			value^ = T(
				clamp(
					extras.click_value +
					f64(
						(global_state.mouse_pos.x - object.click.point.x) /
						box_width(object.box),
					) *
						f64(upper - lower),
					max(lower, lower_limit),
					min(upper, upper_limit),
				),
			)
			draw_frames(1)
		}
		if .Hovered in object.state.current {
			set_cursor(.Resize_EW)
		}
		if object_is_visible(object) {
			radius := current_options().radius
			vgo.push_scissor(vgo.make_box(object.box, radius))
			vgo.fill_box(object.box, paint = style().color.button_background)
			vgo.fill_box(
				get_box_cut_left(
					object.box,
					box_width(object.box) *
					f32(clamp((f64(value^) - lower) / (upper - lower), 0, 1)),
				),
				paint = style().color.button,
			)
			if lower_limit > lower {
				x :=
					object.box.lo.x +
					f32((lower_limit - lower) / (upper - lower)) * box_width(object.box)
				vgo.line({x, object.box.lo.y}, {x, object.box.hi.y}, 1, style().color.accent)
			}
			if upper_limit < upper {
				x :=
					object.box.lo.x +
					f32((upper_limit - lower) / (upper - lower)) * box_width(object.box)
				vgo.line({x, object.box.lo.y}, {x, object.box.hi.y}, 1, style().color.accent)
			}
			vgo.fill_text(
				fmt.tprintf(format, value^),
				style().default_text_size,
				box_center(object.box),
				font = style().monospace_font,
				align = 0.5,
				paint = style().color.content,
			)
			vgo.pop_scissor()
			vgo.stroke_box(object.box, 1, current_options().radius, paint = style().color.button)
		}

		push_id(object.id)
		set_next_box(object.box)
		input(value, format, flags = {.Hidden_Unless_Active, .Select_All})
		pop_id()
	}
	return
}

Range_Slider :: struct {
	using _: Slider,
	value_index: int,
}

range_slider :: proc(
	lower_value: ^$T,
	upper_value: ^T,
	lower, upper: f64,
	min_gap: f64 = 1,
	format: string = "%.2f" when intrinsics.type_is_float(T) else "%i",
	loc := #caller_location,
) where intrinsics.type_is_numeric(T) {
	if lower_value == nil || upper_value == nil {
		return
	}
	object := persistent_object(hash(loc))
	object.size = global_state.style.visual_size * {1, 0.75}
	object.box = next_box(object.size)
	if object.variant == nil {
		object.variant = Range_Slider{}
	}
	extras := &object.variant.(Range_Slider)
	if begin_object(object) {
		defer end_object()

		mouse := mouse_point()
		is_visible := object_is_visible(object)
		handle_object_click(object, true)

		lower_time := clamp((f64(lower_value^) - lower) / (upper - lower), 0, 1)
		upper_time := clamp((f64(upper_value^) - lower) / (upper - lower), 0, 1)
		lower_x := object.box.lo.x + box_width(object.box) * f32(lower_time)
		upper_x := object.box.lo.x + box_width(object.box) * f32(upper_time)
		hovered_index := int(abs(mouse.x - upper_x) < abs(mouse.x - lower_x))

		if .Pressed in object.state.current {
			if .Pressed not_in object.state.previous {
				extras.value_index = hovered_index
				extras.click_value = f64(lower_value^ if extras.value_index == 0 else upper_value^)
			}
			if extras.value_index == 0 {
				lower_value^ = T(
					clamp(
						extras.click_value +
						f64((mouse.x - object.click.point.x) / box_width(object.box)) *
							f64(upper - lower),
						lower,
						f64(upper_value^) - min_gap,
					),
				)
			} else {
				upper_value^ = T(
					clamp(
						extras.click_value +
						f64((mouse.x - object.click.point.x) / box_width(object.box)) *
							f64(upper - lower),
						f64(lower_value^) + min_gap,
						upper,
					),
				)
			}
			draw_frames(1)
		}

		if point_in_box(mouse, object.box) {
			hover_object(object)
		}

		if .Hovered in object.state.current {
			set_cursor(.Resize_EW)
		}

		if is_visible {

			radius := current_options().radius
			vgo.push_scissor(vgo.make_box(object.box, radius))
			vgo.fill_box(object.box, paint = style().color.field)
			value_box := Box{{lower_x, object.box.lo.y}, {upper_x, object.box.hi.y}}
			vgo.fill_box(
				value_box,
				paint = style().color.button,
			)
			if .Hovered in object.state.current {
				if hovered_index == 0 {
					vgo.fill_box({value_box.lo, {value_box.lo.x + 1, value_box.hi.y}}, paint = style().color.accent)
				} else {
					vgo.fill_box({{value_box.hi.x - 1, value_box.lo.y}, {value_box.hi.x, value_box.hi.y}}, paint = style().color.accent)
				}
			}
			vgo.fill_text(
				fmt.tprintf(format, lower_value^),
				style().default_text_size,
				{object.box.lo.x + style().text_padding.x, box_center_y(object.box)},
				font = style().monospace_font,
				align = {0, 0.5},
				paint = style().color.content,
			)
			vgo.fill_text(
				fmt.tprintf(format, upper_value^),
				style().default_text_size,
				{object.box.hi.x - style().text_padding.x, box_center_y(object.box)},
				font = style().monospace_font,
				align = {1, 0.5},
				paint = style().color.content,
			)
			vgo.pop_scissor()
			vgo.stroke_box(object.box, 1, current_options().radius, paint = style().color.button)

			push_id(object.id)
			push_options(default_options())

			was_clicked_in_place := object_was_clicked_in_place(object)
			center_x := box_center_x(object.box)
			click_index := int(mouse_point().x > center_x)

			set_next_box({object.box.lo, {center_x, object.box.hi.y}})
			set_rounded_corners({.Top_Left, .Bottom_Left})
			if was_clicked_in_place && click_index == 0 {
				focus_next_object()
			}
			input(lower_value, format, flags = {.Hidden_Unless_Active, .Monospace})

			set_next_box({{center_x, object.box.lo.y}, object.box.hi})
			set_rounded_corners({.Top_Right, .Bottom_Right})
			if was_clicked_in_place && click_index == 1 {
				focus_next_object()
			}
			input(upper_value, format, flags = {.Hidden_Unless_Active, .Monospace})

			pop_options()
			pop_id()
		}
	}
	return
}

slider_handle :: proc(box: Box, shape: int, loc := #caller_location) -> (pressed, held: bool) {
	object := persistent_object(hash(loc))
	if begin_object(object) {
		object.box = box
		if point_in_box(mouse_point(), object.box) {
			hover_object(object)
		}
		handle_object_click(object, true)
		if object_is_visible(object) {
			vertices: [][2]f32
			switch shape {
			case 0:
				vertices = {
					{object.box.hi.x, object.box.lo.y},
					object.box.hi,
					{object.box.lo.x, object.box.hi.y},
					{object.box.lo.x, object.box.lo.y + box_width(object.box)},
				}
			case 1:
				w := box_width(object.box) / 2
				vertices = {
					{object.box.lo.x, object.box.lo.y + w},
					{object.box.lo.x + w, object.box.lo.y},
					{object.box.hi.x, object.box.lo.y + w},
					object.box.hi,
					{object.box.lo.x, object.box.hi.y},
				}
			case 2:
				vertices = {
					{object.box.hi.x, object.box.lo.y + box_width(object.box)},
					object.box.hi,
					{object.box.lo.x, object.box.hi.y},
					object.box.lo,
				}
			}
			vgo.fill_polygon(
				vertices,
				paint = style().color.accent if .Hovered in object.state.current else style().color.button,
			)
		}

		pressed = .Pressed in (object.state.current - object.state.previous)
		held = .Pressed in object.state.current

		end_object()
	}
	return
}

progress_bar :: proc(time: f32, color: vgo.Color = style().color.accent, loc := #caller_location) {
	time := clamp(time, 0, 1)
	object := persistent_object(hash(loc))
	object.size = global_state.style.visual_size * {1, 0.5}
	object.box = next_box(object.size)
	if begin_object(object) {
		if object_is_visible(object) {
			radius := current_options().radius
			vgo.fill_box(object.box, radius, paint = style().color.foreground_accent)
			vgo.push_scissor(vgo.make_box(object.box, radius))
			vgo.fill_box(
				{object.box.lo, {object.box.lo.x + box_width(object.box) * time, object.box.hi.y}},
				paint = color,
			)
			vgo.pop_scissor()
		}
		end_object()
	}
}

dial :: proc(time: f32, color: vgo.Color = style().color.accent, loc := #caller_location) {
	time := clamp(time, 0, 1)
	object := persistent_object(hash(loc))
	object.size = style().visual_size.y * 2
	object.box = next_box(object.size)
	if begin_object(object) {
		if object_is_visible(object) {
			width := f32(4)
			radius := min(box_width(object.box), box_height(object.box)) / 2
			center := box_center(object.box)
			ring_radius := width / 2
			extra_angle := (ring_radius / (radius - ring_radius) * 2)
			start_angle := f32(math.PI * 0.75)
			end_angle := f32(math.PI * 2.25)

			arc_shape := vgo.make_arc(center, start_angle, end_angle, radius - width, radius)

			start_angle -= extra_angle
			end_angle += extra_angle

			arc_shape.paint = vgo.paint_index_from_option(style().color.foreground_accent)
			vgo.add_shape(arc_shape)
			vgo.push_scissor(arc_shape)
			vgo.arc(
				center,
				start_angle,
				start_angle + (end_angle - start_angle) * time,
				radius - width,
				radius,
				square = true,
				paint = color,
			)
			vgo.pop_scissor()
		}
		end_object()
	}
}

pie :: proc(values: []f32, total: f32, colors: []vgo.Color = {}, loc := #caller_location) {
	object := persistent_object(hash(loc))
	object.size = style().visual_size.y * 2
	object.box = next_box(object.size)
	if begin_object(object) {
		if object_is_visible(object) {
			radius := min(box_width(object.box), box_height(object.box)) / 2
			center := box_center(object.box)
			angle := f32(0)
			for value, i in values {
				slice_angle := (value / total) * math.TAU
				slice_color := style().color.accent
				if len(colors) > 0 {
					slice_color = colors[i % len(colors)]
				}
				vgo.fill_pie(center, angle, angle + slice_angle, radius, paint = slice_color)
				angle += slice_angle
			}
		}
		end_object()
	}
}
