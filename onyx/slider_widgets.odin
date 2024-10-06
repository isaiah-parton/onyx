package onyx

import "base:intrinsics"
import "core:math"
import "core:math/linalg"

Slider_Info :: struct($T: typeid) where intrinsics.type_is_numeric(T) {
	using _: Widget_Info,
	value:   ^T,
	lo, hi:  T,
}

init_slider :: proc(info: ^Slider_Info($T), loc := #caller_location) -> bool {
	info.id = hash(loc)
	info.self = get_widget(info.id) or_return
	info.sticky = true
	info.desired_size = {core.style.visual_size.x, core.style.visual_size.y * 0.75}
	info.hi = max(info.hi, info.lo + 1)
	return true
}

add_slider :: proc(using info: ^Slider_Info($T)) -> bool {
	begin_widget(info) or_return
	defer end_widget()

	_box := self.box
	h := box_height(_box)
	_box.lo.y += h / 4
	_box.hi.y -= h / 4

	radius := box_height(_box) / 2

	if self.visible {
		draw_rounded_box_fill(_box, radius, core.style.color.substance)
	}

	if value == nil {
		// Draw nil text
		return false
	}

	time := clamp(f32(value^ - lo) / f32(hi - lo), 0, 1)
	range_width := box_width(_box) - radius * 2

	knob_center := _box.lo + radius + {time * range_width, 0}
	knob_radius := h / 2

	if point_in_box(core.mouse_pos, _box) ||
	   linalg.distance(knob_center, core.mouse_pos) <= knob_radius {
		hover_widget(self)
	}

	if self.visible {
		draw_rounded_box_fill(
			{_box.lo, {knob_center.x, _box.hi.y}},
			radius,
			fade(core.style.color.accent, 0.5),
		)
		draw_circle_fill(knob_center, knob_radius, core.style.color.accent)
	}

	if (.Pressed in self.state) && value != nil {
		new_time := clamp((core.mouse_pos.x - _box.lo.x - radius) / range_width, 0, 1)
		value^ = lo + T(new_time) * (hi - lo)
		core.draw_next_frame = true
	}

	return true
}

slider :: proc(info: Slider_Info($T), loc := #caller_location) -> Slider_Info(T) {
	info := info
	if init_slider(&info, loc) {
		add_slider(&info)
	}
	return info
}

init_box_slider :: proc(using info: ^Slider_Info($T), loc := #caller_location) -> bool {
	info.id = hash(loc)
	info.self = get_widget(info.id) or_return
	info.sticky = true
	info.desired_size = core.style.visual_size
	info.hi = max(info.hi, info.lo + 1)
	return true
}

add_box_slider :: proc(using info: ^Slider_Info($T)) -> bool {
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

box_slider :: proc(info: Slider_Info($T), loc := #caller_location) -> Slider_Info(T) {
	info := info
	if init_slider(&info, loc) {
		add_box_slider(&info)
	}
	return info
}
