package onyx

import "../vgo"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:slice"

tab :: proc(text: string, active: bool, loc := #caller_location) -> (clicked: bool) {
	object := persistent_object(hash(loc))
	if begin_object(object) {
		text_layout := vgo.make_text_layout(text, style().default_text_size, style().default_font)
		object.size = text_layout.size + style().text_padding * 2
		object.box = next_box(object.size)
		if point_in_box(mouse_point(), object.box) {
			hover_object(object)
		}
		handle_object_click(object)
		if .Hovered in object.state.current {
			set_cursor(.Pointing_Hand)
		}
		if object_is_visible(object) {
			if active {
				vgo.fill_box(object.box, current_options().radius * {1, 1, 0, 0}, paint = style().color.foreground)
			} else {
				vgo.fill_box(shrink_box(object.box, 2), current_options().radius, paint = vgo.mix(0.5, style().color.foreground_accent, style().color.foreground))
			}
			vgo.fill_text_layout(text_layout, box_center(object.box), 0.5, paint = style().color.content)
		}
		clicked = .Clicked in object.state.current
		end_object()
	}
	return
}

// Many_2_One_Widget :: struct {
// 	using object:  ^Object,
// 	index:         int,
// 	items:         []string,
// 	label_layouts: []vgo.Text_Layout,
// }

// Toggle_Widget :: struct {
// 	object: ^Object,
// 	state:  bool,
// }

// Tab :: struct {
// 	using __toggle_widget: Toggle_Widget,
// 	text_layout:           vgo.Text_Layout,
// 	active_time:           f32,
// 	hover_time:            f32,
// }

// Tabs :: Many_2_One_Widget

// tab :: proc(text: string, state: bool, loc := #caller_location) -> (clicked: bool) {
// 	object := persistent_object(hash(loc))
// 	if object.variant == nil {
// 		object.variant = Tab {
// 			object = object,
// 		}
// 	}
// 	object := &object.variant.(Tab)
// 	object.state = state
// 	object.text_layout = vgo.make_text_layout(
// 		text,
// 		global_state.style.default_text_size,
// 		global_state.style.default_font,
// 	)
// 	object.size = object.text_layout.size + {20, 10}
// 	if begin_object(object.object) {
// 		clicked = .Clicked in object.object.state.previous
// 		end_object()
// 	}
// 	return
// }

// display_tab :: proc(object: ^Tab) {
// 	handle_object_click(object.object)
// 	if point_in_box(global_state.mouse_pos, object.object.box) {
// 		hover_object(object.object)
// 	}
// 	if .Hovered in object.object.state.current {
// 		set_cursor(.Pointing_Hand)
// 	}

// 	object.hover_time = animate(object.hover_time, 0.1, .Hovered in object.object.state.current)
// 	object.active_time = animate(object.active_time, 0.15, object.state)

// 	if object_is_visible(object.object) {
// 		center_x := box_center_x(object.object.box)
// 		box := get_box_cut_bottom(
// 			object.object.box,
// 			box_height(object.object.box) * math.lerp(f32(0.85), f32(1.0), object.active_time),
// 		)
// 		vgo.fill_box(
// 			box,
// 			{
// 				global_state.style.rounding * object.active_time,
// 				global_state.style.rounding * object.active_time,
// 				0,
// 				0,
// 			},
// 			paint = vgo.mix(
// 				math.lerp(f32(0.25), f32(1.0), max(object.hover_time * 0.5, object.active_time)),
// 				style().color.background,
// 				style().color.foreground
// 			),
// 		)
// 		vgo.fill_text_layout(
// 			object.text_layout,
// 			box_center(box),
// 			align = 0.5,
// 			paint = style().color.accent_content,
// 		)
// 	}
// }

// tabs :: proc(items: []string, index: ^$T, loc := #caller_location) {
// 	object := persistent_object(hash(loc))
// 	if object.variant == nil {
// 		object.variant = Tabs {
// 			object = object,
// 		}
// 	}
// 	object.metrics.desired_size.y = global_state.style.visual_size.y
// 	for item, i in items {
// 		object.label_layouts[i] = vgo.make_text_layout(
// 			item,
// 			global_state.style.default_text_size,
// 			global_state.style.default_font,
// 		)
// 	}
// 	if begin_object(object) {
// 		defer end_object()
// 		if object_was_changed(object) {
// 			index^ = T(object.index)
// 		} else {
// 			object.index = int(index^)
// 		}
// 	}
// }

// display_tabs :: proc(object: ^Tabs) {

// 	handle_object_click(object)

// 	if point_in_box(global_state.mouse_pos, object.box) {
// 		hover_object(object)
// 	}

// 	is_visible := object_is_visible(object)
// 	inner_box := shrink_box(object.box, 1)
// 	option_size := (inner_box.hi.x - inner_box.lo.x) / f32(len(object.items))

// 	for item, i in object.items {
// 		option_box := cut_box_left(&inner_box, object.label_layouts[i].size.x)
// 		hovered :=
// 			(object.state.current >= {.Hovered}) && point_in_box(global_state.mouse_pos, option_box)
// 		if object.index != i {
// 			if hovered {
// 				if .Clicked in object.state.current {
// 					object.index = i
// 					object.state.current += {.Changed}
// 				}
// 				global_state.cursor_type = .Pointing_Hand
// 			}
// 		}
// 		if is_visible {
// 			vgo.fill_box(
// 				{{option_box.lo.x, option_box.hi.y - 3}, {option_box.hi.x, option_box.hi.y}},
// 				1.5,
// 				paint = vgo.fade(
// 					style().color.content,
// 					f32(int(hovered || object.index == i)),
// 				),
// 			)
// 			vgo.fill_text_layout(
// 				object.label_layouts[i],
// 				{box_center_x(option_box), option_box.lo.y},
// 				align = {0.5, 0},
// 				paint = vgo.fade(style().color.content, 1 if object.index == i else 0.5),
// 			)
// 		}
// 	}
// }

option_slider :: proc(items: []string, index: ^$T, loc := #caller_location) {
	if index == nil {
		return
	}
	object := persistent_object(hash(loc))
	object.size = global_state.style.visual_size
	object.box = next_box(object.size)
	if begin_object(object) {
		defer end_object()

		handle_object_click(object)

		if point_in_box(global_state.mouse_pos, object.box) {
			hover_object(object)
		}

		is_visible := object_is_visible(object)
		inner_box := shrink_box(object.box, 1)
		if is_visible {
			vgo.fill_box(object.box, global_state.style.rounding, style().color.field)
		}
		option_rounding :=
			global_state.style.rounding * ((box_height(object.box) - 4) / box_height(object.box))
		option_size := (inner_box.hi.x - inner_box.lo.x) / f32(len(items))

		for item, i in items {
			option_box := cut_box_left(&inner_box, option_size)
			hovered :=
				(object.state.current >= {.Hovered}) && point_in_box(global_state.mouse_pos, option_box)
			if int(index^) != i {
				if hovered {
					if .Pressed in object.state.current && index^ != T(i) {
						index^ = T(i)
						object.state.current += {.Changed}
					}
					global_state.cursor_type = .Pointing_Hand
				}
			}
			if is_visible {
				vgo.fill_box(
					shrink_box(option_box, 1),
					option_rounding,
					paint = vgo.fade(
						style().color.foreground,
						max(f32(int(hovered)) * 0.5, f32(int(index^ == T(i)))),
					),
				)
				vgo.fill_text(
					item,
					global_state.style.default_text_size,
					box_center(option_box),
					font = global_state.style.default_font,
					align = 0.5,
					paint = vgo.fade(style().color.content, 1 if int(index^) == i else 0.5),
				)
			}
		}
	}
}
