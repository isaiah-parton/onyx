package onyx

import "../vgo"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:slice"



Many_2_One_Widget :: struct {
	using object: ^Object,
	index:        int,
	items:        []string,
}

Tabs :: Many_2_One_Widget

tabs :: proc(items: []string, index: ^$T, loc := #caller_location) {
	object := persistent_object(hash(loc))
	if object.variant == nil {
		object.variant = Tabs {
			object = object,
		}
	}
	self := &object.variant.(Tabs)
	self.items = items
	self.placement = next_user_placement()
	self.metrics.desired_size = global_state.style.visual_size
	if begin_object(object) {
		defer end_object()
		if object_was_changed(object) {
			index^ = T(self.index)
		} else {
			self.index = int(index^)
		}
	}
}

display_tabs :: proc(self: ^Tabs) {

	handle_object_click(self)

	if point_in_box(global_state.mouse_pos, self.box) {
		hover_object(self)
	}

	is_visible := object_is_visible(self)
	inner_box := shrink_box(self.box, 1)
	if is_visible {
		vgo.fill_box(self.box, global_state.style.rounding, global_state.style.color.field)
	}
	option_rounding := global_state.style.rounding * ((box_height(self.box) - 4) / box_height(self.box))
	option_size := (inner_box.hi.x - inner_box.lo.x) / f32(len(self.items))

	for item, i in self.items {
		option_box := cut_box_left(&inner_box, option_size)
		hovered := (self.state.current >= {.Hovered}) && point_in_box(global_state.mouse_pos, option_box)
		if self.index != i {
			if hovered {
				if .Clicked in self.state.current {
					self.index = i
					self.state.current += {.Changed}
				}
				global_state.cursor_type = .Pointing_Hand
			}
		}
		if is_visible {
			vgo.fill_box(
				shrink_box(option_box, 1),
				option_rounding,
				paint = vgo.fade(
					global_state.style.color.fg,
					f32(int(hovered || self.index == i)),
				),
			)
			vgo.fill_text(
				item,
				global_state.style.default_text_size,
				box_center(option_box),
				font = global_state.style.default_font,
				align = 0.5,
				paint = vgo.fade(global_state.style.color.content, 1 if self.index == i else 0.5),
			)
		}
	}
}

Option_Slider :: Many_2_One_Widget

option_slider :: proc(items: []string, index: ^$T, loc := #caller_location) {
	object := persistent_object(hash(loc))
	if object.variant == nil {
		object.variant = Tabs {
			object = object,
		}
	}
	self := &object.variant.(Option_Slider)
	self.items = items
	self.placement = next_user_placement()
	self.metrics.desired_size = global_state.style.visual_size
	if begin_object(object) {
		defer end_object()
		if object_was_changed(object) {
			index^ = T(self.index)
		} else {
			self.index = int(index^)
		}
	}
}

display_option_slider :: proc(self: ^Option_Slider) {

	handle_object_click(self)

	if point_in_box(global_state.mouse_pos, self.box) {
		hover_object(self)
	}

	is_visible := object_is_visible(self)
	inner_box := shrink_box(self.box, 1)
	if is_visible {
		vgo.fill_box(self.box, global_state.style.rounding, global_state.style.color.field)
	}
	option_rounding := global_state.style.rounding * ((box_height(self.box) - 4) / box_height(self.box))
	option_size := (inner_box.hi.x - inner_box.lo.x) / f32(len(self.items))

	for item, i in self.items {
		option_box := cut_box_left(&inner_box, option_size)
		hovered := (self.state.current >= {.Hovered}) && point_in_box(global_state.mouse_pos, option_box)
		if self.index != i {
			if hovered {
				if .Clicked in self.state.current {
					self.index = i
					self.state.current += {.Changed}
				}
				global_state.cursor_type = .Pointing_Hand
			}
		}
		if is_visible {
			vgo.fill_box(
				shrink_box(option_box, 1),
				option_rounding,
				paint = vgo.fade(
					global_state.style.color.fg,
					f32(int(hovered || self.index == i)),
				),
			)
			vgo.fill_text(
				item,
				global_state.style.default_text_size,
				box_center(option_box),
				font = global_state.style.default_font,
				align = 0.5,
				paint = vgo.fade(global_state.style.color.content, 1 if self.index == i else 0.5),
			)
		}
	}
}
