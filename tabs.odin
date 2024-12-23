package onyx

import "../vgo"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:slice"

Many_2_One_Widget :: struct {
	using object:  ^Object,
	index:         int,
	items:         []string,
	label_layouts: []vgo.Text_Layout,
}

Toggle_Widget :: struct {
	object: ^Object,
	state:  bool,
}

Tab :: struct {
	using __toggle_widget: Toggle_Widget,
	text_layout:           vgo.Text_Layout,
	bar_opacity:           f32,
}

Tabs :: Many_2_One_Widget

tab :: proc(text: string, state: bool, loc := #caller_location) -> (clicked: bool) {
	object := persistent_object(hash(loc))
	if object.variant == nil {
		object.variant = Tab {
			object = object,
		}
	}
	self := &object.variant.(Tab)
	self.state = state
	self.text_layout = vgo.make_text_layout(
		text,
		global_state.style.default_text_size,
		global_state.style.default_font,
	)
	self.object.metrics.desired_size = self.text_layout.size + {20, 10}
	self.object.placement = next_user_placement()
	if begin_object(self.object) {
		clicked = .Clicked in self.object.state.previous
		end_object()
	}
	return
}

display_tab :: proc(self: ^Tab) {
	handle_object_click(self.object)
	if point_in_box(global_state.mouse_pos, self.object.box) {
		hover_object(self.object)
	}
	if .Hovered in self.object.state.current {
		set_cursor(.Pointing_Hand)
	}

	self.bar_opacity +=
		(max(f32(i32(.Hovered in self.object.state.current)) * 0.5, f32(i32(self.state))) -
			self.bar_opacity) *
		15 *
		global_state.delta_time

	if object_is_visible(self.object) {
		center_x := box_center_x(self.object.box)
		vgo.fill_box(
			{
				{self.object.box.lo.x, self.object.box.hi.y - 2},
				{self.object.box.hi.x, self.object.box.hi.y},
			},
			paint = vgo.fade(global_state.style.color.content, self.bar_opacity),
		)
		vgo.fill_text_layout(
			self.text_layout,
			box_center(self.object.box) + {0, -2},
			align = 0.5,
			paint = global_state.style.color.content,
		)
	}
}

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
	self.metrics.desired_size.y = global_state.style.visual_size.y
	self.label_layouts = make([]vgo.Text_Layout, len(items), allocator = context.temp_allocator)
	for item, i in items {
		self.label_layouts[i] = vgo.make_text_layout(
			item,
			global_state.style.default_text_size,
			global_state.style.default_font,
		)
	}
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
	option_size := (inner_box.hi.x - inner_box.lo.x) / f32(len(self.items))

	for item, i in self.items {
		option_box := cut_box_left(&inner_box, self.label_layouts[i].size.x)
		hovered :=
			(self.state.current >= {.Hovered}) && point_in_box(global_state.mouse_pos, option_box)
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
				{{option_box.lo.x, option_box.hi.y - 3}, {option_box.hi.x, option_box.hi.y}},
				1.5,
				paint = vgo.fade(
					global_state.style.color.content,
					f32(int(hovered || self.index == i)),
				),
			)
			vgo.fill_text_layout(
				self.label_layouts[i],
				{box_center_x(option_box), option_box.lo.y},
				align = {0.5, 0},
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
	option_rounding :=
		global_state.style.rounding * ((box_height(self.box) - 4) / box_height(self.box))
	option_size := (inner_box.hi.x - inner_box.lo.x) / f32(len(self.items))

	for item, i in self.items {
		option_box := cut_box_left(&inner_box, option_size)
		hovered :=
			(self.state.current >= {.Hovered}) && point_in_box(global_state.mouse_pos, option_box)
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
