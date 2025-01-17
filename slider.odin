package onyx

import "../vgo"
import "base:intrinsics"
import "core:fmt"
import "core:math"
import "core:math/linalg"

slider :: proc(
	value: ^$T,
	lower, upper: T,
	format: string = "%.2f" when intrinsics.type_is_float(T) else "%i",
	loc := #caller_location,
) where intrinsics.type_is_numeric(T) {
	if value == nil {
		return
	}
	object := persistent_object(hash(loc))
	object.size = global_state.style.visual_size * {1, 0.75}
	object.box = next_box(object.size)
	if begin_object(object) {
		defer end_object()

		mouse := mouse_point()
		is_visible := object_is_visible(object)
		handle_object_click(object, true)

		if (.Pressed in object.state.current) {
			new_time := clamp((mouse.x - object.box.lo.x) / box_width(object.box), 0, 1)
			value^ = lower + T(f64(new_time) * f64(upper - lower))
			draw_frames(1)
		}

		time := clamp((value^ - lower) / (upper - lower), 0, 1)

		if point_in_box(mouse, object.box) {
			hover_object(object)
		}

		if .Hovered in object.state.current {
			set_cursor(.Resize_EW)
		}

		if is_visible {
			radius := current_options().radius
			vgo.push_scissor(vgo.make_box(object.box, radius))
			vgo.fill_box(
				object.box,
				paint = vgo.mix(1.0 / 3.0, style().color.foreground, style().color.substance),
			)
			vgo.fill_box(
				get_box_cut_left(object.box, box_width(object.box) * time),
				paint = style().color.substance,
			)
			vgo.stroke_box(object.box, 1, radius, paint = style().color.substance)
			vgo.fill_text(
				fmt.tprintf(format, value^),
				style().default_text_size,
				box_center(object.box),
				font = style().monospace_font,
				align = 0.5,
				paint = style().color.content,
			)
			vgo.pop_scissor()
		}
	}
}

progress_bar :: proc(
	time: f32,
	color: vgo.Color = style().color.accent,
	loc := #caller_location,
) {
	time := clamp(time, 0, 1)
	object := persistent_object(hash(loc))
	object.size = global_state.style.visual_size * {1, 0.5}
	object.box = next_box(object.size)
	if begin_object(object) {
		if object_is_visible(object) {
			radius := current_options().radius
			vgo.fill_box(object.box, radius, paint = style().color.field)
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

dial :: proc(
	time: f32,
	color: vgo.Color = style().color.accent,
	loc := #caller_location,
) {
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

			arc_shape := vgo.make_arc(
				center,
				start_angle,
				end_angle,
				radius - width,
				radius,
			)

			start_angle -= extra_angle
			end_angle += extra_angle

			arc_shape.paint = vgo.paint_index_from_option(style().color.field)
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

pie :: proc(
	values: []f32,
	total: f32,
	colors: []vgo.Color = {},
	loc := #caller_location,
) {
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
