package onyx

import "../vgo"
import "base:intrinsics"
import "core:fmt"
import "core:math"
import "core:math/linalg"

slider :: proc(value: ^$T, lower, upper: T, format: string = "%v", loc := #caller_location) where intrinsics.type_is_numeric(T) {
	if value == nil {
		return
	}
	object := persistent_object(hash(loc))
	object.size = global_state.style.visual_size
	if begin_object(object) {
		defer end_object()

		box := object.box
		h := box_height(box)
		box = shrink_box(box, h / 4)
		radius := box_height(box) / 2
		range_width := box_width(box) - radius * 2
		colors := colors()
		mouse := mouse_point()
		is_visible := object_is_visible(object)
		handle_object_click(object, true)

		if is_visible {
			vgo.fill_box(box, radius, paint = colors.field)
		}

		if (.Pressed in object.state.current) {
			new_time := clamp((mouse.x - box.lo.x - radius) / range_width, 0, 1)
			value^ = lower + f64(new_time) * (upper - lower)
			draw_frames(1)
		}

		time := clamp((value^ - lower) / (upper - lower), 0, 1)

		knob_center := box.lo + radius + {f32(time) * range_width, 0}
		knob_radius := h / 2

		if point_in_box(mouse, box) ||
		   linalg.distance(knob_center, mouse) <= knob_radius {
			hover_object(object)
		}

		if is_visible {
			vgo.fill_box(
				{box.lo, {knob_center.x, box.hi.y}},
				radius,
				vgo.mix(1.0 / 3.0, colors.accent, vgo.BLACK),
			)
			vgo.fill_circle(knob_center, knob_radius, colors.accent)
		}
	}
}

	// if .Pressed in slider.state {
	// 	text_layout := vgo.make_text_layout(
	// 		fmt.tprintf(format.? or_else "%v", value^),
	// 		core.style.monospace_font,
	// 		core.style.default_text_size,
	// 	)
	// 	tooltip_size := linalg.max(
	// 		text_layout.size + core.style.tooltip_padding * 2,
	// 		[2]f32{50, 0},
	// 	)
	// 	if slider.tooltip_size == {} {
	// 		slider.tooltip_size = tooltip_size
	// 	} else {
	// 		slider.tooltip_size +=
	// 			(tooltip_size - slider.tooltip_size) * 10 * core.delta_time
	// 	}
	// 	push_id(slider.id)
	// 	defer pop_id()
	// 	if tooltip(
	// 		{
	// 			origin = Box{knob_center - knob_radius, knob_center + knob_radius},
	// 			size = slider.tooltip_size,
	// 			side = .Top,
	// 		},
	// 	) {
	// 		vgo.fill_text_layout_aligned(
	// 			text_layout,
	// 			box_center(layout_box()),
	// 			.Center,
	// 			.Center,
	// 			colors.content,
	// 		)
	// 	}
	// }
