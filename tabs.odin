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
	active_time:           f32,
	hover_time:            f32,
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
	object.size = self.text_layout.size + {20, 10}
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

	self.hover_time = animate(self.hover_time, 0.1, .Hovered in self.object.state.current)
	self.active_time = animate(self.active_time, 0.15, self.state)

	if object_is_visible(self.object) {
		center_x := box_center_x(self.object.box)
		box := get_box_cut_bottom(
			self.object.box,
			box_height(self.object.box) * math.lerp(f32(0.85), f32(1.0), self.active_time),
		)
		vgo.fill_box(
			box,
			{
				global_state.style.rounding * self.active_time,
				global_state.style.rounding * self.active_time,
				0,
				0,
			},
			paint = vgo.mix(
				math.lerp(f32(0.25), f32(1.0), max(self.hover_time * 0.5, self.active_time)),
				global_state.style.color.bg[0],
				global_state.style.color.fg
			),
		)
		vgo.fill_text_layout(
			self.text_layout,
			box_center(box),
			align = 0.5,
			paint = global_state.style.color.accent_content,
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
