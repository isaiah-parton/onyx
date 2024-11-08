package onyx
// Widgets are things you click on to do stuff.
import "base:intrinsics"
import "base:runtime"
import "core:fmt"
import "core:math"
import "core:math/ease"
import "core:math/linalg"
import "core:mem"
import "core:strings"
import "core:time"
import "tedit"
import "../../vgo"

// Delay for compound clicking
MAX_CLICK_DELAY :: time.Millisecond * 450

Widget_Flag :: enum {
	Is_Input,
	Persistent,
}

Widget_Flags :: bit_set[Widget_Flag;u8]

Widget_Variant :: union {
	Button,
	Boolean,
	Container,
}

// Interaction state
Widget_Status :: enum {
	// Transient
	Hovered,
	Focused,
	Pressed,
	Changed,
	Clicked,
	// Persistent
	Open,
	Active,
}

Widget_State :: bit_set[Widget_Status;u8]

WIDGET_STATE_ALL :: Widget_State{.Hovered, .Focused, .Pressed, .Changed, .Clicked, .Open, .Active}

// The widget struct is pretty monolithic rn
Widget :: struct {
	// Unique hashed id
	id:                 Id,
	// This should be the total visually occupied space
	box:                Box,
	// Home layer
	layer:              ^Layer,
	// If the widget is visible and should be displayed
	visible:            bool,
	// This only disables interaction
	disabled:           bool,
	// When this is true, the widget will be destroyed next time
	// `new_frame()` is called.
	dead:               bool,
	// Internally handled bit flags
	flags:              Widget_Flags,
	// Interaction state
	last_state:         Widget_State,
	next_state:         Widget_State,
	state:              Widget_State,
	// Which widget states can be passed to this widget
	in_state_mask:      Widget_State,
	// Which widget states will be passed to the parent widget
	out_state_mask:     Widget_State,
	// Click information
	click_count:        int,
	click_time:         time.Time,
	click_point: [2]f32,
	click_button:       Mouse_Button,
	// Desired size stored to be passed to the layout
	desired_size:       [2]f32,
	// Offset of visual position
	offset: [2]f32,
	click_offset: [2]f32,
	// Widget chaining for forms
	// these values are transient
	prev:               ^Widget,
	next:               ^Widget,
	// Stores the number of the last frame on which this widget was updated
	// This is to avoid calling the same widget more than once per frame
	// Also protects the `variant` field from being misused.
	frames:             int,
	variant:            Widget_Variant,
	// Generic state used by most widgets
	focus_time:         f32,
	hover_time:         f32,
	press_time: f32,
	open_time:          f32,
	disable_time:       f32,
}

// Animation
animate :: proc(value, duration: f32, condition: bool) -> f32 {
	value := value

	if condition {
		if value < 1 {
			global_state.draw_this_frame = true
			global_state.draw_next_frame = true
			value = min(1, value + global_state.delta_time * (1 / duration))
		}
	} else if value > 0 {
		global_state.draw_this_frame = true
		global_state.draw_next_frame = true
		value = max(0, value - global_state.delta_time * (1 / duration))
	}

	return value
}

// Process all widgets
process_widgets :: proc() {

	global_state.last_focused_widget = global_state.focused_widget
	global_state.last_hovered_widget = global_state.hovered_widget

	// Make sure dragged widgets are hovered
	if global_state.dragged_widget != 0 {
		global_state.hovered_widget = global_state.dragged_widget
	} else {
		global_state.hovered_widget = global_state.next_hovered_widget
	}

	// Reset next hover id so if nothing is hovered nothing will be hovered
	global_state.next_hovered_widget = 0

	if (global_state.mouse_bits - global_state.last_mouse_bits) > {} {
		global_state.focused_widget = global_state.hovered_widget
	}
}

enable_widgets :: proc(enabled: bool = true) {
	global_state.disable_widgets = !enabled
}

current_widget :: proc() -> Maybe(^Widget) {
	if global_state.widget_stack.height > 0 {
		return global_state.widget_stack.items[global_state.widget_stack.height - 1]
	}
	return nil
}

new_widget :: proc(id: Id) -> ^Widget {
	widget := new(Widget)
	widget.id = id
	widget.out_state_mask = WIDGET_STATE_ALL
	global_state.widget_map[id] = widget
	global_state.draw_this_frame = true
	assert(widget != nil)
	return widget
}

destroy_widget :: proc(widget: ^Widget) {

}

get_widget :: proc(id: Id) -> ^Widget {
	return global_state.widget_map[id] or_else new_widget(id)
}

widget_was_updated_this_frame :: proc(widget: ^Widget) -> bool {
	return widget.frames >= global_state.frames
}

handle_widget_click :: proc(widget: ^Widget, sticky: bool = false) {
	if global_state.hovered_widget == widget.id {
		// Add hovered state
		widget.state += {.Hovered}
		// Clicking
		pressed_buttons := global_state.mouse_bits - global_state.last_mouse_bits
		if pressed_buttons != {} {
			if widget.click_button == global_state.mouse_button &&
			   time.since(widget.click_time) <= MAX_CLICK_DELAY {
				widget.click_count = max((widget.click_count + 1) % 4, 1)
			} else {
				widget.click_count = 1
			}
			widget.click_button = global_state.mouse_button
			widget.click_point = global_state.mouse_pos
			widget.click_time = time.now()
			widget.state += {.Pressed}
			global_state.draw_this_frame = true
			global_state.focused_widget = widget.id
			// Set the globally dragged widget
			if sticky do global_state.dragged_widget = widget.id
		}
		// TODO: Lose click if mouse moved too much (allow for dragging containers by their contents)
		// if !info.sticky && linalg.length(core.click_mouse_pos - core.mouse_pos) > 8 {
		// 	widget.state -= {.Pressed}
		// 	widget.click_count = 0
		// }
	} else if global_state.dragged_widget != widget.id  /* Keep hover and press state if dragged */{
		widget.state -= {.Pressed, .Hovered}
		widget.click_count = 0
	}
	// Mouse press
	if widget.state >= {.Pressed} {
		// Check for released buttons
		released_buttons := global_state.last_mouse_bits - global_state.mouse_bits
		if global_state.mouse_button in released_buttons {
			widget.state += {.Clicked}
			widget.state -= {.Pressed}
			global_state.dragged_widget = 0
		}
	} else {
		// Reset click time if cursor is moved beyond a threshold
		if widget.click_count > 0 && linalg.length(global_state.mouse_pos - global_state.last_mouse_pos) > 2 {
			widget.click_count = 0
		}
	}
}

begin_widget :: proc(widget: ^Widget) -> bool {
	if widget == nil do return false

	widget.dead = false

	if widget_was_updated_this_frame(widget) {
		vgo.fill_box(
			widget.box,
			paint = vgo.Color{
				0 = 255,
				3 = u8(
					128.0 +
					math.sin(time.duration_seconds(time.since(global_state.start_time)) * 12.0) * 64.0,
				),
			},
		)
		when ODIN_DEBUG {
			fmt.printfln("Widget ID collision: %i", widget.id)
		}
		return false
	}
	widget.frames = global_state.frames

	// Push to the stack
	push_stack(&global_state.widget_stack, widget) or_return
	// Widget must have a valid layer
	widget.layer = current_layer().? or_return
	// Set visible flag
	widget.visible = global_state.visible && get_clip(widget.layer.box, widget.box) != .Full
	// Reset state
	widget.last_state = widget.state
	widget.state -= {.Clicked, .Focused, .Changed}
	// Disabled?
	if global_state.disable_widgets do widget.disabled = true
	widget.disable_time = animate(widget.disable_time, 0.25, widget.disabled)
	// Compute next frame's layout
	layout := current_layout().?
	// If the user set an explicit size with either `set_width()` or `set_height()` the widget's desired size should reflect that
	// The purpose of these checks is that `set_size_fill()` makes content shrink to accommodate scrollbars
	if layout.next_size.x == 0 || layout.next_size.x != box_width(layout.box) {
		widget.desired_size.x = max(widget.desired_size.x, layout.next_size.x)
	}
	if layout.next_size.y == 0 || layout.next_size.y != box_height(layout.box) {
		widget.desired_size.y = max(widget.desired_size.y, layout.next_size.y)
	}
	// Focus state
	if global_state.focused_widget == widget.id {
		widget.state += {.Focused}
	}
	// Update form
	if global_state.form_active {
		if global_state.form.first == nil {
			global_state.form.first = widget
		}
		if global_state.form.last != nil {
			widget.prev = global_state.form.last
			global_state.form.last.next = widget
		}
		global_state.form.last = widget
	}
	// Reset next state
	widget.state += widget.next_state
	widget.next_state = {}
	return true
}

end_widget :: proc() {
	if widget, ok := current_widget().?; ok {
		// Draw debug box
		when ODIN_DEBUG {
			if global_state.debug.enabled {
				if vgo.disable_scissor() {
					vgo.stroke_box(widget.box, 1, paint = vgo.GREEN)
				}
			}
		}
		// Transfer state to layer
		widget.layer.state += widget.state
		// Update layout
		if layout, ok := current_layout().?; ok {
			add_layout_content_size(
				layout,
				box_size(widget.box) if layout.fixed else widget.desired_size,
			)
		}
		// Pop the stack
		pop_stack(&global_state.widget_stack)
		// Transfer state to parent
		if parent, ok := current_widget().?; ok {
			transfer_widget_state_to_parent(widget, parent)
		}
	}
}

transfer_widget_state_to_parent :: proc(child: ^Widget, parent: ^Widget) {
	state_mask := child.out_state_mask & parent.in_state_mask
	if .Pressed in child.state && child.id == global_state.dragged_widget {
		state_mask -= {.Pressed}
	}
	parent.next_state += child.state & state_mask
}

hover_widget :: proc(widget: ^Widget) {
	if widget.disabled do return
	if widget.layer.index < global_state.hovered_layer_index do return
	if !point_in_box(global_state.mouse_pos, widget.layer.box) do return
	global_state.next_hovered_widget = widget.id
	global_state.next_hovered_layer = widget.layer.id
	global_state.hovered_layer_index = widget.layer.index
}

focus_widget :: proc(widget: ^Widget) {
	global_state.focused_widget = widget.id
}

foreground :: proc(loc := #caller_location) {
	layout, ok := current_layout().?
	if !ok do return
	widget := get_widget(hash(loc))
	if begin_widget(widget) {
		defer end_widget()
		if widget.variant == nil {
			widget.in_state_mask = WIDGET_STATE_ALL
		}
		widget.box = layout.box
		vgo.fill_box(widget.box, global_state.style.rounding, paint = global_state.style.color.fg)
		if point_in_box(global_state.mouse_pos, widget.box) {
			hover_widget(widget)
		}
	}
}

background :: proc(loc := #caller_location) {
	layout, ok := current_layout().?
	if !ok do return
	widget := get_widget(hash(loc))
	if begin_widget(widget) {
		defer end_widget()
		if widget.variant == nil {
			widget.in_state_mask = WIDGET_STATE_ALL
		}
		widget.box = layout.box
		vgo.fill_box(widget.box, global_state.style.rounding, global_state.style.color.field)
		if point_in_box(global_state.mouse_pos, widget.box) {
			hover_widget(widget)
		}
	}
}

spinner :: proc(loc := #caller_location) {
	widget := get_widget(hash(loc))
	if begin_widget(widget) {
		defer end_widget()

		vgo.spinner(box_center(widget.box), box_height(widget.box) * 0.5, global_state.style.color.substance)
	}
}

// skeleton :: proc(loc := #caller_location) {
// 	info := Widget_Info {
// 		id = hash(loc),
// 	}
// 	if begin_widget(&info) {
// 		defer end_widget()
// 		draw_skeleton(info.self.box, core.style.rounding)
// 	}
// }

draw_skeleton :: proc(box: Box, rounding: f32) {
	vgo.fill_box(box, rounding, global_state.style.color.substance)
	vgo.fill_box(box, rounding, vgo.Paint{kind = .Skeleton})

	global_state.draw_this_frame = true
}

divider :: proc() {
	cut := snapped_box(cut_current_layout(size = [2]f32{1, 1}))
	layout := current_layout().?
	layout.content_size[int(layout.next_cut_side) / 2] += 1
	vgo.fill_box(cut, paint = global_state.style.color.substance)
}
