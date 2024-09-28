package onyx

import "base:intrinsics"
import "core:math"
import "core:math/linalg"

Slider_Info :: struct {
	using _: Widget_Info,
	value:   ^f64,
	lo, hi:  f64,
}

init_slider :: proc(info: ^Slider_Info, loc := #caller_location) -> bool {
	info.id = hash(loc)
	info.self = get_widget(info.id.?) or_return
	info.sticky = true
	info.desired_size = core.style.visual_size
	info.hi = max(info.hi, info.lo + 1)
	return true
}

add_slider :: proc(using info: ^Slider_Info) -> bool {
	begin_widget(info) or_return
	defer end_widget()

	h := box_height(self.box)
	radius := h / 2

	if self.visible {
		draw_rounded_box_fill(self.box, radius, core.style.color.substance)
	}

	if value == nil {
		// Draw nil text
		return false
	}

	self.box.lo.y += h / 4
	self.box.hi.y -= h / 4

	time := clamp(f32(value^ - lo) / f32(hi - lo), 0, 1)
	range_width := box_width(self.box) - radius * 2

	knob_center := self.box.lo + radius + {time * range_width, 0}
	knob_radius := h / 2

	if point_in_box(core.mouse_pos, self.box) ||
	   linalg.distance(knob_center, core.mouse_pos) <= knob_radius {
		hover_widget(self)
	}

	if self.visible {
		draw_rounded_box_fill(
			{self.box.lo, {self.box.lo.x + box_width(self.box) * time, self.box.hi.y}},
			radius,
			core.style.color.accent,
		)
		draw_arc_fill(knob_center, knob_radius, 0, math.TAU, core.style.color.background)
		draw_arc_stroke(knob_center, knob_radius, 0, math.TAU, 1.5, core.style.color.accent)
	}

	if (.Pressed in self.state) && value != nil {
		new_time := clamp((core.mouse_pos.x - self.box.lo.x - radius) / range_width, 0, 1)
		value^ = lo + f64(new_time) * (info.hi - info.lo)
		core.draw_next_frame = true
	}

	return true
}

slider :: proc(info: Slider_Info, loc := #caller_location) -> Slider_Info {
	info := info
	init_slider(&info, loc)
	add_slider(&info)
	return info
}

add_box_slider :: proc(using info: ^Slider_Info) -> bool {
	begin_widget(info) or_return
	defer end_widget()

	horizontal_slider_behavior(self)
	if self.visible {
		draw_box_fill(self.box, core.style.color.substance)
		time := clamp(f32(value^ - lo) / f32(hi - lo), 0, 1)
		draw_box_fill(
			{self.box.lo, {self.box.lo.x + box_width(self.box) * time, self.box.hi.y}},
			core.style.color.accent,
		)
	}
	if .Pressed in self.state {
		new_time := clamp((core.mouse_pos.x - self.box.lo.x) / box_width(self.box), 0, 1)
		value^ = lo + f64(new_time * f32(hi - lo))
		core.draw_next_frame = true
	}
	return true
}

box_slider :: proc(info: Slider_Info, loc := #caller_location) -> Slider_Info {
	info := info
	init_slider(&info, loc)
	add_slider(&info)
	return info
}
