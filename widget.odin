package ui

import "core:fmt"
import "core:time"
import "core:math"
import "core:math/ease"
import "core:math/linalg"
import "core:runtime"

DOUBLE_CLICK_TIME :: 450

Widget :: struct {
	id: Id,
	box: Box,
	layer: ^Layer,
	disabled,
	draggable,
	dead: bool,
	last_state,
	state: Widget_State,

	hover_time: f32,

	click_count: int,
	click_time: time.Time,
	click_button: Mouse_Button,
}
// Interaction state
Widget_Status :: enum {
	// Has status
	Hovered,
	Focused,
	Pressed,
	// Data modified
	Changed,
	// Pressed and released
	Clicked,
}
Widget_State :: bit_set[Widget_Status;u8]
/*
	Generic info for calling widgets	
*/
Generic_Widget_Info :: struct {
	disabled: bool,
	id: Maybe(Id),
	box: Maybe(Box),
	corners: Corners,
	// tooltip: Maybe(Tooltip_Info),
	// options: Widget_Options,
}
Generic_Widget_Result :: struct {
	self: Maybe(^Widget),
}
// Animation
animate :: proc(value, duration: f32, condition: bool) -> f32 {
	value := value
	if condition {
		if value < 1 {
			core.draw_next_frame = true
			value = min(1, value + core.delta_time * (1 / duration))
		}
	} else if value > 0 {
		core.draw_next_frame = true
		value = max(0, value - core.delta_time * (1 / duration))
	}
	return value
}
// [SECTION] Results
was_clicked :: proc(result: Generic_Widget_Result, button: Mouse_Button = .Left, times: int = 1) -> bool {
	widget := result.self.?
	return .Clicked in widget.state && widget.click_button == button && widget.click_count >= times
}
is_hovered :: proc(result: Generic_Widget_Result) -> bool {
	widget := result.self.?
	return .Hovered in widget.state
}
// [SECTION] Processing
get_widget :: proc(info: Generic_Widget_Info, loc: runtime.Source_Code_Location = #caller_location) -> ^Widget {
	id := info.id.? or_else hash(loc)
	widget, ok := core.widget_map[id]
	if !ok {
		for i in 0..<MAX_WIDGETS {
			if core.widgets[i] == nil {
				core.widgets[i] = Widget{
					id = id,
				}
				widget = &core.widgets[i].?
				core.widget_map[id] = widget
				when ODIN_DEBUG {
					fmt.printf("[ui] Created widget %x\n", id)
				}
				core.draw_next_frame = true
				break
			}
		}
	}
	widget.dead = false
	widget.disabled = info.disabled
	widget.layer = current_layer()
	if box, ok := info.box.?; ok {
		widget.box = box
	}
	return widget
}
// Process all widgets
process_widgets :: proc() {
	core.last_hovered_widget = core.hovered_widget
	core.hovered_widget = core.next_hovered_widget
	// Make sure dragged widgets are hovered
	if core.dragged_widget != 0 {
		core.hovered_widget = core.dragged_widget
	}
	// Reset next hover id so if nothing is hovered nothing will be hovered
	core.next_hovered_widget = 0
	// Press whatever is hovered and focus what is pressed
	if mouse_pressed(.Left) {
		core.draw_this_frame = true
	}
	// Reset drag status
	if mouse_released(.Left) {
		core.dragged_widget = 0
	}
	// Free unused widgets
	for id, widget in core.widget_map {
		if widget.dead {
			when ODIN_DEBUG {
				fmt.printf("[ui] Deleted widget %x\n", id)
			}
			delete_key(&core.widget_map, id)
			(transmute(^Maybe(Widget))widget)^ = nil
			core.draw_next_frame = true
		} else {
			widget.dead = false
		}
	}
}
// Commit a widget to be processed
commit_widget :: proc(widget: ^Widget, hovered: bool) {
	if !(core.dragged_widget != 0 && widget.id != core.hovered_widget) && core.hovered_layer == widget.layer.id && hovered {
		core.next_hovered_widget = widget.id
	}
	// If hovered
	widget.last_state = widget.state
	// Mouse hover
	if core.hovered_widget == widget.id {
		// Add hovered state
		widget.state += {.Hovered}
		// Set time of hover
		if core.last_hovered_widget != widget.id {
			// widget.hover_time = time.now()
		}
		// Clicking
		pressed_buttons := core.mouse_bits - core.last_mouse_bits
		if pressed_buttons != {} {
			if widget.click_count == 0 {
				widget.click_button = core.mouse_button
			}
			if widget.click_button == core.mouse_button && time.since(widget.click_time) <= DOUBLE_CLICK_TIME {
				widget.click_count = max((widget.click_count + 1) % 3, 1)
			} else {
				widget.click_count = 1
			}
			widget.click_button = core.mouse_button
			widget.click_time = time.now()
			widget.state += {.Pressed}
		}
	} else {
		widget.state -= {.Pressed, .Hovered}
		widget.click_count = 0
	}
	if widget.state >= {.Pressed} {
		// Just released buttons
		released_buttons := core.last_mouse_bits - core.mouse_bits
		if released_buttons != {} {
			for button in Mouse_Button {
				if button == widget.click_button {
					widget.state += {.Clicked}
					break
				}
			}
		}
		if widget.draggable do core.dragged_widget = widget.id
	}
}
// [SECTION] Buttons
Button_Kind :: enum {
	Primary,
	Secondary,
	Outlined,
	Ghost,
}
Button_Info :: struct {
	using _: Generic_Widget_Info,
	text: string,
	kind: Button_Kind,
}
Button_Result :: struct {
	using _: Generic_Widget_Result,
}
measure_button :: proc(desc: Button_Info) -> (width: f32) {
	return
}
button :: proc(info: Button_Info, loc := #caller_location) -> (res: Button_Result) {
	widget := get_widget(info, loc)
	text_info: Text_Info = {
		text = info.text,
		font = core.style.font,
		size = 18,//core.style.button_text_size,
	}
	text_size := measure_text(text_info)
	size := text_size + {20, 10}

	layout := current_layout()
	widget.box = cut_box(&layout.box, layout.content_side, size.x if int(layout.content_side) > 1 else size.y)
	widget.box.low = linalg.floor(widget.box.low)
	widget.box.high = linalg.floor(widget.box.high)
	widget.hover_time = animate(widget.hover_time, 0.1, .Hovered in widget.state)

	switch info.kind {
		case .Outlined:
		if widget.hover_time < 1 {
			draw_rounded_box_stroke(widget.box, core.style.rounding, 1, core.style.color.substance)
		}
		draw_rounded_box_fill(widget.box, core.style.rounding, fade(core.style.color.substance, widget.hover_time))
		draw_text(center(widget.box) - text_size / 2, text_info, core.style.color.content)
		case .Secondary:
		draw_rounded_box_fill(widget.box, core.style.rounding, blend_colors(widget.hover_time * 0.25, core.style.color.substance, core.style.color.foreground))
		draw_text(center(widget.box) - text_size / 2, text_info, core.style.color.content)
		case .Primary:
		draw_rounded_box_fill(widget.box, core.style.rounding, blend_colors(widget.hover_time * 0.25, core.style.color.content, core.style.color.foreground))
		text_info.font = core.style.thin_font
		draw_text(center(widget.box) - text_size / 2, text_info, core.style.color.foreground)
		case .Ghost:
		draw_rounded_box_fill(widget.box, core.style.rounding, fade(core.style.color.substance, widget.hover_time))
		draw_text(center(widget.box) - text_size / 2, text_info, core.style.color.content)
	}

	hovered := point_in_box(core.mouse_pos, widget.box)
	if hovered {
		core.cursor_type = .POINTING_HAND
	}
	commit_widget(widget, hovered)
	return
}
