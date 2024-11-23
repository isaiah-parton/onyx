package onyx

import "../vgo"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:slice"

Tabs :: struct {
	using object: ^Object,
	index:        int,
	items:        []string,
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

// add_tabs :: proc(using info: ^Tabs_Info) -> bool {
// 	begin_object(info) or_return
// 	defer end_object()

// 	push_id(self.id)
// 	defer pop_id()

// 	if layout({box = self.box, isolated = true}) {
// 		set_side(.Left)
// 		set_width_percent(100.0 / f32(len(options)))
// 		set_height_fill()
// 		for option, o in options {
// 			push_id(o + 1)
// 			defer pop_id()

// 			tab_info := Object_Info {
// 				id            = hash("tab"),
// 				in_state_mask = Object_State{.Hovered},
// 			}
// 			if begin_object(&tab_info) {
// 				tab_info.self.open_time = animate(tab_info.self.open_time, 0.15, index^ == o)
// 				button_behavior(tab_info.self)
// 				if tab_info.self.visible {
// 					bg_color := vgo.blend(
// 					global_state.style.color.field,
// 						global_state.style.color.fg,
// 						tab_info.self.open_time,
// 					)
// 					vgo.fill_box(
// 						tab_info.self.box,
// 						{global_state.style.rounding, global_state.style.rounding, 0, 0},
// 						paint = bg_color,
// 					)
// 					vgo.push_scissor(vgo.make_box(tab_info.self.box))
// 					defer vgo.pop_scissor()
// 					text_layout := vgo.make_text_layout(option, global_state.style.default_font, 16)
// 					vgo.fill_text_layout(
// 						text_layout,
// 						{
// 							tab_info.self.box.lo.x + global_state.style.text_padding.x,
// 							box_center_y(tab_info.self.box),
// 						},
// 						vgo.fade(
// 							global_state.style.color.content,
// 							math.lerp(f32(0.5), f32(1.0), tab_info.self.open_time),
// 						),
// 					)
// 					gradient_size := min(box_width(tab_info.self.box), 80)
// 					if text_layout.size.x > box_width(tab_info.self.box) - gradient_size {

// 					}
// 				}

// 				if .Hovered in (tab_info.self.state + tab_info.self.last_state) {
// 					if button({id = hash("close"), text = "\ueb99", style = .Ghost, box = shrink_box(get_box_cut_right(tab_info.self.box, box_height(tab_info.self.box)), 4)}).clicked {
// 						closed_index = o
// 					}
// 				}

// 				if .Clicked in tab_info.self.state {
// 					index^ = o
// 				}

// 				end_object()
// 			}
// 		}
// 	}

// 	return true
// }
