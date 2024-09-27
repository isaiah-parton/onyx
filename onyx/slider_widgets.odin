package onyx

import "base:intrinsics"
import "core:math"
import "core:math/linalg"

Slider_Info :: struct {
	using _:       Widget_Info,
	value: ^f64,
	lo, hi: f64,
}

Slider :: struct {
	using info: Slider_Info,
}

Slider_Result :: Widget_Result

make_slider :: proc(info: Slider_Info, loc := #caller_location) -> (slider: Slider, ok: bool) {
	if info.value == nil do return
	ok = true
	slider.info := info
	slider.id = hash(loc)
	slider.desired_size = core.style.visual_size
	slider.hi = max(slider.hi, slider.lo + 1)
	slider.sticky = true
	return
}

add_slider :: proc(slider: Slider) -> (result: Slider_Result, ok: bool) {
	begin_widget(slider)

	h := box_height(slider.self.box)

	widget.box.lo.y += h / 4
	widget.box.hi.y -= h / 4

	radius := box_height(widget.box) / 2
	time := clamp(f32(info.value - info.lo) / f32(info.hi - info.lo), 0, 1)
	range_width := box_width(widget.box) - radius * 2

	knob_center := widget.box.lo + radius + {time * range_width, 0}
	knob_radius := h / 2

	if point_in_box(core.mouse_pos, widget.box) ||
	   linalg.distance(knob_center, core.mouse_pos) <= knob_radius {
		hover_widget(widget)
	}

	if widget.visible {
		draw_rounded_box_fill(widget.box, radius, core.style.color.substance)
		draw_rounded_box_fill(
			{widget.box.lo, {widget.box.lo.x + box_width(widget.box) * time, widget.box.hi.y}},
			radius,
			core.style.color.accent,
		)
		draw_arc_fill(knob_center, knob_radius, 0, math.TAU, core.style.color.background)
		draw_arc_stroke(knob_center, knob_radius, 0, math.TAU, 1.5, core.style.color.accent)
	}

	if .Pressed in widget.state {

		new_time := clamp((core.mouse_pos.x - widget.box.lo.x - radius) / range_width, 0, 1)

		assert(slider.value != nil)
		slider.value^ = info.lo + (new_time * (info.hi - info.lo))

		core.draw_next_frame = true
	}

	end_widget()
	return
}

slider :: proc(info: Slider_Info, loc := #caller_location) -> (result: Slider_Result, ok: bool) {
	return add_slider(make_slider(info, loc) or_return)
}

add_box_slider :: proc(slider: Slider) -> (result: Slider_Result) {
	begin_widget(slider)
	defer end_widget()

	horizontal_slider_behavior(slider)

	if slider.visible {
		draw_box_fill(slider.box, core.style.color.substance)
		time := clamp(f32(info.value - info.lo) / f32(info.hi - info.lo), 0, 1)
		draw_box_fill({slider.box.lo, {slider.box.lo.x + box_width(slider.box) * time, slider.box.hi.y}}, core.style.color.accent)
	}
	if .Pressed in slider.state {

		time := clamp((core.mouse_pos.x - slider.box.lo.x) / box_width(slider.box), 0, 1)

		assert(slider.value != nil)
		slider.value^ = info.lo + (time * f32(info.hi - info.lo))

		core.draw_next_frame = true
	}
	return
}

box_slider :: proc(info: Slider_Info, loc := #caller_location) -> (result: Slider_Result, ok: bool) {
	return add_box_slider(make_slider(info, loc) or_return)
}
