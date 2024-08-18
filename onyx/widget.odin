package onyx

import "core:fmt"
import "core:time"

import "core:math"
import "core:math/ease"
import "core:math/linalg"

import "base:intrinsics"
import "base:runtime"

DOUBLE_CLICK_TIME :: time.Millisecond * 450

Widget :: struct {
	id:                                           Id,
	box:                                          Box,
	layer:                                        ^Layer,
	visible, disabled, draggable, is_field, dead: bool,
	last_state, next_state, state:                Widget_State,
	focus_time, hover_time, disable_time:         f32,
	click_count:                                  int,
	click_time:                                   time.Time,
	click_button:                                 Mouse_Button,
	allocator:                                    runtime.Allocator,
	variant:                                      Widget_Variant,
	desired_size:                                 [2]f32,
}

Widget_Variant :: union {
	Graph_Widget_Variant,
	Widget_Variant_Tooltip,
	Widget_Variant_Tabs,
	Text_Input_Widget_Variant,
	Switch_Widget_Variant,
}

// Interaction state
Widget_Status :: enum {
	Hovered,
	Focused,
	Pressed,
	Changed,
	Clicked,
	Open,
}

Widget_State :: bit_set[Widget_Status;u8]

Generic_Widget_Info :: struct {
	id:           Maybe(Id),
	box:          Maybe(Box),
	fixed_size:   bool,
	desired_size: [2]f32,
	disabled:     bool,
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

was_clicked :: proc(
	result: Generic_Widget_Result,
	button: Mouse_Button = .Left,
	times: int = 1,
) -> bool {
	widget := result.self.? or_return
	return .Clicked in widget.state && widget.click_button == button && widget.click_count >= times
}

is_hovered :: proc(result: Generic_Widget_Result) -> bool {
	widget := result.self.? or_return
	return .Hovered in widget.state
}

was_changed :: proc(result: Generic_Widget_Result) -> bool {
	widget := result.self.? or_return
	return .Changed in widget.state
}

get_widget :: proc(info: Generic_Widget_Info) -> (widget: ^Widget, ok: bool) {
	id := info.id.? or_return
	widget, ok = core.widget_map[id]
	if !ok {
		for i in 0 ..< MAX_WIDGETS {
			if core.widgets[i] == nil {
				core.widgets[i] = Widget {
					id        = id,
					allocator = runtime.arena_allocator(&core.arena),
				}
				widget = &core.widgets[i].?
				core.widget_map[id] = widget

				when ODIN_DEBUG {
					fmt.printf("[core] Created widget %x\n", id)
				}

				ok = true

				core.draw_next_frame = true
				break
			}
		}
	}

	// Widget must have a valid layer
	widget.layer = current_layer().? or_return

	widget.visible = core.visible && core.draw_this_frame
	widget.dead = false
	if box, ok := info.box.?; ok {
		widget.box = box
	}
	widget.last_state = widget.state
	widget.state -= {.Clicked, .Focused, .Changed}

	widget.desired_size = info.desired_size

	widget.disabled = true if core.disable_widgets else info.disabled
	widget.disable_time = animate(widget.disable_time, 0.25, widget.disabled)

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
			if widget.click_button == core.mouse_button &&
			   time.since(widget.click_time) <= DOUBLE_CLICK_TIME {
				widget.click_count = max((widget.click_count + 1) % 4, 1)
			} else {
				widget.click_count = 1
			}
			widget.click_button = core.mouse_button
			widget.click_time = time.now()
			widget.state += {.Pressed}
			if widget.draggable do core.dragged_widget = widget.id
		}
	} else if core.dragged_widget != widget.id {
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
					widget.state -= {.Pressed}
					break
				}
			}
		}
	}

	if core.focused_widget == widget.id {
		widget.state += {.Focused}
	}

	widget.state += widget.next_state
	widget.next_state = {}

	return
}

widget_variant :: proc(widget: ^Widget, $T: typeid) -> ^T {
	if variant, ok := &widget.variant.(T); ok {
		return variant
	}
	widget.variant = T{}
	return &widget.variant.(T)
}

// Process all widgets
process_widgets :: proc() {

	core.last_focused_widget = core.focused_widget
	core.last_hovered_widget = core.hovered_widget

	// Make sure dragged widgets are hovered
	if core.dragged_widget != 0 {
		core.hovered_widget = core.dragged_widget
	} else {
		core.hovered_widget = core.next_hovered_widget
	}

	// Reset next hover id so if nothing is hovered nothing will be hovered
	core.next_hovered_widget = 0

	// Press whatever is hovered and focus what is pressed
	if mouse_pressed(.Left) {
		core.focused_widget = core.hovered_widget
		core.draw_this_frame = true
	}

	// Reset drag state
	if mouse_released(.Left) {
		core.dragged_widget = 0
	}
}

// Commit a widget to be processed
commit_widget :: proc(widget: ^Widget, hovered: bool) {
	if (.Hovered in widget.layer.state) && hovered && !widget.disabled {
		core.next_hovered_widget = widget.id
	}
	layout := current_layout().?
	add_layout_content_size(layout, widget.desired_size)
}

enable_widgets :: proc(enabled: bool = true) {
	core.disable_widgets = !enabled
}
