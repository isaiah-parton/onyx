package onyx

import "../vgo"
import "base:intrinsics"
import "core:fmt"
import "core:math"
import "core:math/linalg"

Slider :: struct {
	using object: ^Object,
	value: f64,
	lower: f64,
	upper: f64,
	new_value: Maybe(f64),
	format: string,
	axis: Axis,
}

slider :: proc(value: ^$T, lower, upper: T, format: string = "%v", loc := #caller_location) where intrinsics.type_is_numeric(T) {
	object := persistent_object(hash(loc))
	if value == nil do return
	if begin_object(object) {
		defer end_object()

		if object.variant == nil {
			object.variant = Slider{
				object = object,
			}
		}
		slider := &object.variant.(Slider)
		if new_value, ok := slider.new_value.?; ok {
			value^ = T(new_value)
		}
		slider.lower = lower
		slider.upper = upper
		slider.format = format
		slider.value = f64(value^)
		slider.metrics.desired_size = global_state.style.visual_size
	}
}

display_slider :: proc(self: ^Slider) {

	box := self.box
	h := box_height(box)
	box = shrink_box(box, h / 4)
	radius := box_height(box) / 2
	range_width := box_width(box) - radius * 2
	colors := colors()
	mouse := mouse_point()
	is_visible := object_is_visible(self)
	handle_object_click(self, true)

	if is_visible {
		vgo.fill_box(box, radius, paint = colors.field)
	}

	if (.Pressed in self.state.current) {
		new_time := clamp((mouse.x - box.lo.x - radius) / range_width, 0, 1)
		self.new_value = self.lower + f64(new_time) * (self.upper - self.lower)
		draw_frames(1)
	}

	time := clamp((self.value - self.lower) / (self.upper - self.lower), 0, 1)

	knob_center := box.lo + radius + {f32(time) * range_width, 0}
	knob_radius := h / 2

	if point_in_box(mouse, box) ||
	   linalg.distance(knob_center, mouse) <= knob_radius {
		hover_object(self)
	}

	if is_visible {
		vgo.fill_box(
			{box.lo, {knob_center.x, box.hi.y}},
			radius,
			vgo.mix(0.333, colors.accent, vgo.BLACK),
		)
		vgo.fill_circle(knob_center, knob_radius, colors.accent)
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
}
