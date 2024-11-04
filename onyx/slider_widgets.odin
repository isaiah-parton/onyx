package onyx

import "base:intrinsics"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "../../vgo"

Slider_Info :: struct($T: typeid) where intrinsics.type_is_numeric(T) {
	using _: Widget_Info,
	value:   ^T,
	lo, hi:  T,
	format:  Maybe(string),
}

Slider_State :: struct {
	tooltip_size: [2]f32,
}

init_slider :: proc(using info: ^Slider_Info($T), loc := #caller_location) -> bool {
	if id == 0 do id = hash(loc)
	self = get_widget(id) or_return
	sticky = true
	desired_size = {core.style.visual_size.x, core.style.visual_size.y * 0.75}
	hi = max(hi, lo + 1)
	return true
}

add_slider :: proc(using info: ^Slider_Info($T)) -> bool {
	begin_widget(info) or_return
	defer end_widget()

	_box := self.box
	h := box_height(_box)
	_box = shrink_box(_box, h / 4)

	radius := box_height(_box) / 2

	if self.visible {
		vgo.fill_box(_box, radius, paint = core.style.color.substance)
	}

	if value == nil {
		// Draw nil text
		return false
	}

	range_width := box_width(_box) - radius * 2

	if (.Pressed in self.state) && value != nil {
		new_time := clamp((core.mouse_pos.x - _box.lo.x - radius) / range_width, 0, 1)
		value^ = T(f32(lo) + new_time * f32(hi - lo))
		core.draw_this_frame = true
	}

	time := clamp(f32(value^ - lo) / f32(hi - lo), 0, 1)

	knob_center := _box.lo + radius + {time * range_width, 0}
	knob_radius := h / 2

	if point_in_box(core.mouse_pos, _box) ||
	   linalg.distance(knob_center, core.mouse_pos) <= knob_radius {
		hover_widget(self)
	}

	if self.visible {
		vgo.fill_box(
			{_box.lo, {knob_center.x, _box.hi.y}},
			radius,
			vgo.fade(core.style.color.accent, 0.5),
		)
		vgo.fill_circle(knob_center, knob_radius, core.style.color.accent)
	}

	if .Pressed in self.state {
		text_layout := vgo.make_text_layout(
			fmt.tprintf(format.? or_else "%v", value^),
			core.style.monospace_font,
			18,
		)
		tooltip_size := linalg.max(text_layout.size + core.style.tooltip_padding * 2, [2]f32{50, 0})
		if self.slider.tooltip_size == {} {
			self.slider.tooltip_size = tooltip_size
		} else {
			self.slider.tooltip_size += (tooltip_size - self.slider.tooltip_size) * 10 * core.delta_time
		}
		push_id(self.id)
		defer pop_id()
		if tooltip(
			{
				origin = Box{knob_center - knob_radius, knob_center + knob_radius},
				size = self.slider.tooltip_size,
				side = .Top,
			},
		) {
			vgo.fill_text_layout_aligned(text_layout, box_center(layout_box()), .Center, .Center, core.style.color.content)
		}
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
	if id == 0 do id = hash(loc)
	self = get_widget(id) or_return
	sticky = true
	desired_size = core.style.visual_size
	hi = max(hi, lo + 1)
	return true
}

add_box_slider :: proc(using info: ^Slider_Info($T)) -> bool {
	begin_widget(info) or_return
	defer end_widget()

	horizontal_slider_behavior(self)
	if self.visible {
		vgo.fill_box(self.box, paint = core.style.color.substance)
		time := clamp(f32(value^ - lo) / f32(hi - lo), 0, 1)
		vgo.fill_box(
			{self.box.lo, {self.box.lo.x + box_width(self.box) * time, self.box.hi.y}},
			paint = core.style.color.accent,
		)
	}
	if .Pressed in self.state {
		new_time := clamp((core.mouse_pos.x - self.box.lo.x) / box_width(self.box), 0, 1)
		value^ = lo + T(new_time * f32(hi - lo))
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
