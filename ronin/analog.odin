package ronin

import kn "local:katana"
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
	self := get_object(hash(loc))
	self.size = {10, 2} * get_current_style().scale
	if self.variant == nil {
		self.variant = Slider{}
		self.flags += {.Sticky_Press, .Sticky_Hover}
	}
	extras := &self.variant.(Slider)
	if do_object(self) {
		if point_in_box(mouse_point(), self.box) {
			hover_object(self)
		}

		if object_was_clicked_in_place(self) {
			focus_next_object()
		}

		if .Pressed in self.state.current {
			if .Pressed not_in self.state.previous {
				extras.click_value = f64(value^)
			}
			new_value := T(
				clamp(
					extras.click_value +
					f64(
						(global_state.mouse_pos.x - self.click.point.x) /
						box_width(self.box),
					) *
						f64(upper - lower),
					max(lower, lower_limit),
					min(upper, upper_limit),
				),
			)
			if value^ != new_value {
				self.state.current += {.Changed}
				value^ = new_value
			}
			draw_frames(1)
		}
		if .Hovered in self.state.current {
			set_cursor(.Resize_EW)
		}
		if object_is_visible(self) {
			style := get_current_style()
			radius := get_current_options().radius
			kn.push_scissor(kn.make_box(self.box, radius))
			kn.add_box(self.box, paint = style.color.button_background)
			kn.add_box(
				get_box_cut_left(
					self.box,
					box_width(self.box) *
					f32(clamp((f64(value^) - lower) / (upper - lower), 0, 1)),
				),
				paint = style.color.button,
			)
			if lower_limit > lower {
				x :=
					self.box.lo.x +
					f32((lower_limit - lower) / (upper - lower)) * box_width(self.box)
				kn.add_line({x, self.box.lo.y}, {x, self.box.hi.y}, 1, style.color.accent)
			}
			if upper_limit < upper {
				x :=
					self.box.lo.x +
					f32((upper_limit - lower) / (upper - lower)) * box_width(self.box)
				kn.add_line({x, self.box.lo.y}, {x, self.box.hi.y}, 1, style.color.accent)
			}
			kn.set_font(style.monospace_font)
			kn.add_string(
				fmt.tprintf(format, value^),
				style.default_text_size,
				box_center(self.box),
				align = 0.5,
				paint = style.color.content,
			)
			kn.pop_scissor()
			kn.add_box_lines(self.box, style.line_width, get_current_options().radius, paint = style.color.button)
		}

		push_id(self.id)
		set_next_box(self.box)
		input(value, with_format(format), only_if_active, that_selects_all_when_clicked)
		pop_id()
	}
	return
}

Range_Slider :: struct {
	click_value: f64,
	click_difference: f64,
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
	object := get_object(hash(loc))
	object.size = {1, 0.75} * get_current_style().scale
	if object.variant == nil {
		object.variant = Range_Slider{}
		object.flags += {.Sticky_Press, .Sticky_Hover}
	}
	extras := &object.variant.(Range_Slider)
	if do_object(object) {

		mouse := mouse_point()
		is_visible := object_is_visible(object)

		lower_time := clamp((f64(lower_value^) - lower) / (upper - lower), 0, 1)
		upper_time := clamp((f64(upper_value^) - lower) / (upper - lower), 0, 1)
		lower_x := object.box.lo.x + box_width(object.box) * f32(lower_time)
		upper_x := object.box.lo.x + box_width(object.box) * f32(upper_time)
		hovered_index := int(abs(mouse.x - upper_x) < abs(mouse.x - lower_x))

		if .Pressed in object.state.current {
			if .Shift in object.click.mods {
				if .Pressed not_in object.state.previous {
					extras.click_value = f64(lower_value^)
					extras.click_difference = f64(upper_value^) - f64(lower_value^)
				}
				value := clamp(
					extras.click_value +
					f64((mouse.x - object.click.point.x) / box_width(object.box)) *
						f64(upper - lower),
					lower,
					upper - extras.click_difference,
				)
				lower_value^ = T(value)
				upper_value^ = T(value + extras.click_difference)
			} else {
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
			radius := get_current_options().radius
			kn.push_scissor(kn.make_box(object.box, radius))
			kn.add_box(object.box, paint = get_current_style().color.field)
			value_box := Box{{lower_x, object.box.lo.y}, {upper_x, object.box.hi.y}}
			kn.add_box(
				value_box,
				paint = get_current_style().color.button,
			)
			if .Hovered in object.state.current {
				if hovered_index == 0 || key_down(.Left_Shift) {
					kn.add_box({value_box.lo, {value_box.lo.x + 1, value_box.hi.y}}, paint = get_current_style().color.accent)
				}
				if hovered_index == 1 || key_down(.Left_Shift) {
					kn.add_box({{value_box.hi.x - 1, value_box.lo.y}, {value_box.hi.x, value_box.hi.y}}, paint = get_current_style().color.accent)
				}
			}
			kn.set_font(get_current_style().monospace_font)
			kn.add_string(
				fmt.tprintf(format, lower_value^),
				get_current_style().default_text_size,
				{object.box.lo.x + get_current_style().text_padding.x, box_center_y(object.box)},
				align = {0, 0.5},
				paint = get_current_style().color.content,
			)
			kn.add_string(
				fmt.tprintf(format, upper_value^),
				get_current_style().default_text_size,
				{object.box.hi.x - get_current_style().text_padding.x, box_center_y(object.box)},
				align = {1, 0.5},
				paint = get_current_style().color.content,
			)
			kn.pop_scissor()
			kn.add_box_lines(object.box, 1, get_current_options().radius, paint = get_current_style().color.button)

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
			input(lower_value, with_format(format), only_if_active)

			set_next_box({{center_x, object.box.lo.y}, object.box.hi})
			set_rounded_corners({.Top_Right, .Bottom_Right})
			if was_clicked_in_place && click_index == 1 {
				focus_next_object()
			}
			input(upper_value, with_format(format), only_if_active)

			pop_options()
			pop_id()
		}
	}
	return
}

slider_handle :: proc(box: Box, shape: int, loc := #caller_location) -> (pressed, held: bool) {
	object := get_object(hash(loc))
	object.flags += {.Sticky_Press, .Sticky_Hover}
	if begin_object(object) {
		object.box = box
		if point_in_box(mouse_point(), object.box) {
			hover_object(object)
		}
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
			kn.add_polygon(
				vertices,
				paint = get_current_style().color.accent if .Hovered in object.state.current else get_current_style().color.button,
			)
		}

		pressed = .Pressed in (object.state.current - object.state.previous)
		held = .Pressed in object.state.current

		end_object()
	}
	return
}

progress_bar :: proc(time: f32, color: kn.Color = get_current_style().color.accent, loc := #caller_location) {
	time := clamp(time, 0, 1)
	object := get_object(hash(loc))
	object.size = {5, 1} * get_current_style().scale
	if begin_object(object) {
		if object_is_visible(object) {
			radius := get_current_options().radius
			kn.add_box(object.box, radius, paint = get_current_style().color.background)
			kn.push_scissor(kn.make_box(object.box, radius))
			kn.add_box(
				{object.box.lo, {object.box.lo.x + box_width(object.box) * time, object.box.hi.y}},
				paint = color,
			)
			kn.pop_scissor()
		}
		end_object()
	}
}

dial :: proc(time: f32, color: kn.Color = get_current_style().color.accent, loc := #caller_location) {
	time := clamp(time, 0, 1)
	object := get_object(hash(loc))
	object.size = get_current_style().scale * 2
	if begin_object(object) {
		if object_is_visible(object) {
			width := f32(4)
			radius := min(box_width(object.box), box_height(object.box)) / 2
			center := box_center(object.box)
			ring_radius := width / 2
			extra_angle := (ring_radius / (radius - ring_radius) * 2)
			start_angle := f32(math.PI * 0.75)
			end_angle := f32(math.PI * 2.25)

			arc_shape := kn.make_arc(center, start_angle, end_angle, radius - width, radius)

			start_angle -= extra_angle
			end_angle += extra_angle

			arc_shape.paint = kn.paint_index_from_option(get_current_style().color.background)
			kn.add_shape(arc_shape)
			kn.push_scissor(arc_shape)
			kn.add_arc(
				center,
				start_angle,
				start_angle + (end_angle - start_angle) * time,
				radius - width,
				radius,
				square = true,
				paint = color,
			)
			kn.pop_scissor()
		}
		end_object()
	}
}

pie :: proc(values: []f32, total: f32, colors: []kn.Color = {}, loc := #caller_location) {
	self := get_object(hash(loc))
	self.size = get_current_style().scale * 2
	if do_object(self) {
		if object_is_visible(self) {
		radius := min(box_width(self.box), box_height(self.box)) / 2
		center := box_center(self.box)
			angle := f32(0)
			for value, i in values {
				slice_angle := (value / total) * math.TAU
				slice_color := get_current_style().color.accent
				if len(colors) > 0 {
					slice_color = colors[i % len(colors)]
				}
				kn.add_pie(center, angle, angle + slice_angle, radius, paint = slice_color)
				angle += slice_angle
			}
		}
	}
}
