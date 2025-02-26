package ronin

import kn "local:katana"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:slice"

tab :: proc(text: string, active: bool, loc := #caller_location) -> (clicked: bool) {
	object := get_object(hash(loc))
	if begin_object(object) {
		style := get_current_style()
		kn.set_font(style.bold_font)
		text_layout := kn.make_text(text, style.default_text_size)
		object.size = text_layout.size + style.text_padding * 2
		if point_in_box(mouse_point(), object.box) {
			hover_object(object)
		}
		if .Hovered in object.state.current {
			set_cursor(.Pointing_Hand)
		}
		if object_is_visible(object) {
			if active {
				kn.add_box(object.box, get_current_options().radius * {1, 1, 0, 0}, paint = style.color.foreground)
			} else {
				kn.add_box(shrink_box(object.box, 2), get_current_options().radius, paint = kn.mix(0.5, style.color.foreground_accent, style.color.foreground))
			}
			kn.add_text(text_layout, box_center(object.box) - text_layout.size * 0.5, paint = style.color.content)
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
// 	label_layouts: []kn.Text,
// }

// Toggle_Widget :: struct {
// 	object: ^Object,
// 	state:  bool,
// }

// Tab :: struct {
// 	using __toggle_widget: Toggle_Widget,
// 	text_layout:           kn.Text,
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
// 	object.text_layout = kn.make_text(
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
// 		kn.add_box(
// 			box,
// 			{
// 				global_state.style.rounding * object.active_time,
// 				global_state.style.rounding * object.active_time,
// 				0,
// 				0,
// 			},
// 			paint = kn.mix(
// 				math.lerp(f32(0.25), f32(1.0), max(object.hover_time * 0.5, object.active_time)),
// 				get_current_style().color.background,
// 				get_current_style().color.foreground
// 			),
// 		)
// 		kn.add_text(
// 			object.text_layout,
// 			box_center(box),
// 			align = 0.5,
// 			paint = get_current_style().color.accent_content,
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
// 	object.metrics.desired_size.y = global_state.style.scale.y
// 	for item, i in items {
// 		object.label_layouts[i] = kn.make_text(
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
// 			kn.add_box(
// 				{{option_box.lo.x, option_box.hi.y - 3}, {option_box.hi.x, option_box.hi.y}},
// 				1.5,
// 				paint = kn.fade(
// 					get_current_style().color.content,
// 					f32(int(hovered || object.index == i)),
// 				),
// 			)
// 			kn.add_text(
// 				object.label_layouts[i],
// 				{box_center_x(option_box), option_box.lo.y},
// 				align = {0.5, 0},
// 				paint = kn.fade(get_current_style().color.content, 1 if object.index == i else 0.5),
// 			)
// 		}
// 	}
// }

Option_Slider_Result :: struct {
	changed: bool,
}

option_slider :: proc(items: []string, index: ^$T, loc := #caller_location) -> (result: Option_Slider_Result) {
	if index == nil {
		return
	}
	object := get_object(hash(loc))
	object.size = global_state.style.scale
	if begin_object(object) {
		defer end_object()

		if point_in_box(global_state.mouse_pos, object.box) {
			hover_object(object)
		}

		is_visible := object_is_visible(object)
		inner_box := shrink_box(object.box, 2)
		if is_visible {
			kn.add_box_lines(object.box, 1, get_current_style().rounding, get_current_style().color.button)
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
						result.changed = true
					}
					global_state.cursor_type = .Pointing_Hand
				}
			}
			if is_visible {
				kn.add_box(
					shrink_box(option_box, 1),
					option_rounding,
					paint = kn.fade(
						get_current_style().color.button,
						max(f32(int(hovered)) * 0.5, f32(int(index^ == T(i)))),
					),
				)
				kn.set_font(get_current_style().default_font)
				kn.add_string(
					item,
					global_state.style.default_text_size,
					box_center(option_box),
					align = 0.5,
					paint = kn.fade(get_current_style().color.content, 1 if int(index^) == i else 0.5),
				)
			}
		}
	}
	return
}
