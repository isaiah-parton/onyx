package onyx

import "core:fmt"
import "core:time"

import "core:math"
import "core:math/ease"
import "core:math/linalg"
import "core:mem"

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
	variant:                                      Widget_Kind,
	desired_size:                                 [2]f32,
	frames:                                       int,
}

Widget_Kind :: union {
	Graph_Widget_Kind,
	Menu_Widget_Kind,
	Tooltip_Widget_Kind,
	Tabs_Widget_Kind,
	Text_Input_Widget_Kind,
	Generic_Boolean_Widget_Kind,
	Date_Picker_Widget_Kind,
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
	id:            Maybe(Id),
	box:           Maybe(Box),
	fixed_size:    bool,
	required_size: [2]f32,
	desired_size:  [2]f32,
	disabled:      bool,
}

Generic_Widget_Result :: struct {
	self: Maybe(^Widget),
}

// Animation
animate :: proc(value, duration: f32, condition: bool) -> f32 {
	value := value

	if condition {
		if value < 1 {
			core.draw_this_frame = true
			value = min(1, value + core.delta_time * (1 / duration))
		}
	} else if value > 0 {
		core.draw_this_frame = true
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

widget_kind :: proc(widget: ^Widget, $T: typeid) -> ^T {
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

enable_widgets :: proc(enabled: bool = true) {
	core.disable_widgets = !enabled
}

current_widget :: proc() -> Maybe(^Widget) {
	if core.widget_stack.height > 0 {
		return core.widget_stack.items[core.widget_stack.height - 1]
	}
	return nil
}

begin_widget :: proc(info: Generic_Widget_Info) -> (widget: ^Widget, ok: bool) {
	id := info.id.? or_return
	widget, ok = core.widget_map[id]
	if !ok {
		for i in 0 ..< MAX_WIDGETS {
			if core.widgets[i] == nil {
				core.widgets[i] = Widget {
					id        = id,
					allocator = mem.scratch_allocator(&core.scratch_allocator),
				}
				widget = &core.widgets[i].?
				core.widget_map[id] = widget

				core.draw_this_frame = true

				ok = true
				break
			}
		}
	}

	if widget == nil do return

	if widget.frames == core.frames {
		fmt.printf(
			"Two or more widgets with the same ID '%v' were called in the same frame\n",
			widget.id,
		)
		return nil, false
	}
	widget.frames = core.frames

	// Widget must have a valid layer
	widget.layer = current_layer().? or_return

	// Place widget
	widget.box = info.box.? or_else next_widget_box(info)

	// Keep alive
	widget.dead = false

	// Set visible flag
	widget.visible = core.visible && get_clip(current_clip().?, widget.box) != .Full

	// Reset state
	widget.last_state = widget.state
	widget.state -= {.Clicked, .Focused, .Changed}

	// Disabled?
	widget.disabled = true if core.disable_widgets else info.disabled
	widget.disable_time = animate(widget.disable_time, 0.25, widget.disabled)

	// Compute next frame's layout
	layout := current_layout().?
	// If the user set an explicit size with either `set_width()` or `set_height()` the widget's desired size should reflect that
	// The purpose of these checks is that `set_size_fill()` makes content shrink to accommodate scrollbars
	if layout.next_size.x == 0 || layout.next_size.x != box_width(layout.box) {
		widget.desired_size.x = max(info.desired_size.x, layout.next_size.x)
	}
	if layout.next_size.y == 0 || layout.next_size.y != box_height(layout.box) {
		widget.desired_size.y = max(info.desired_size.y, layout.next_size.y)
	}

	// Mouse hover
	if core.hovered_widget == widget.id {
		// Add hovered state
		widget.state += {.Hovered}
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
	// Mouse press
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
	// Focus state
	if core.focused_widget == widget.id {
		widget.state += {.Focused}
	}
	// Reset next state
	widget.state += widget.next_state
	widget.next_state = {}
	// Push to the stack
	ok = push_stack(&core.widget_stack, widget)
	return
}

end_widget :: proc() {
	widget := current_widget().?
	layout := current_layout().?
	add_layout_content_size(layout, widget.desired_size)
	pop_stack(&core.widget_stack)
}

hover_widget :: proc(widget: ^Widget) {
	// Disabled?
	if widget.disabled do return
	// Layer not hovered?
	if core.hovered_layer != widget.layer.id do return
	// Clipped?
	if clip, ok := current_clip().?; ok && !point_in_box(core.mouse_pos, current_clip().?) do return
	// Ok hover
	core.next_hovered_widget = widget.id
}

focus_widget :: proc(widget: ^Widget) {
	core.focused_widget = widget.id
}
