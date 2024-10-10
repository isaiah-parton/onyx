package onyx
// Widgets are things you click on to do stuff.
import "base:intrinsics"
import "base:runtime"
import "core:fmt"
import "core:math"
import "core:math/ease"
import "core:math/linalg"
import "core:mem"
import "core:time"

MAX_CLICK_DELAY :: time.Millisecond * 450
// The internal widget structure
Widget :: struct {
	id:                                              Id,
	box:                                             Box,
	layer:                                           ^Layer,
	// Interaction options
	visible, disabled, dead:                         bool,
	// TODO: Replace this with chaining
	is_field:                                        bool,
	// Interaction state
	last_state, next_state, state:                   Widget_State,
	focus_time, hover_time, open_time, disable_time: f32,
	// Click information
	click_count:                                     int,
	click_time:                                      time.Time,
	click_button:                                    Mouse_Button,
	desired_size:                                    [2]f32,
	// Stores the number of the last frame on which this widget was updated
	frames:                                          int,
	on_death:                                        proc(_: ^Widget),
	variant:                                         Widget_Kind,
	// using variant: struct #raw_union {
	// 	menu: Menu_Widget_Kind,
	// 	graph: Graph_Widget_Kind,
	// 	tooltip: Tooltip_Widget_Kind,
	// 	tabs: Tabs_Widget_Kind,
	// 	input: Input_Widget_Kind,
	// 	boolean: Boolean_Widget_Kind,
	// 	date: Date_Picker_Widget_Kind,
	// 	table: Table_Widget_Kind,
	// },
}
// Widget variants
// 	I'm using a union for safety, idk if it's really necessary
Widget_Kind :: union {
	Menu_Widget_Kind,
	Graph_Widget_Kind,
	Tooltip_Widget_Kind,
	Tabs_Widget_Kind,
	Input_Widget_Kind,
	Boolean_Widget_Kind,
	Date_Picker_Widget_Kind,
	Table_Widget_Kind,
	Color_Conversion_Widget_Kind,
}
// Interaction state
Widget_Status :: enum {
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
// A generic descriptor for all widgets
Widget_Info :: struct {
	self:         ^Widget,
	id:           Id,
	// Optional box to be used instead of cutting from the layout
	box:          Maybe(Box),
	disabled:     bool,
	sticky:       bool,
	fixed_size:   bool,
	// Size required by the user
	// required_size: [2]f32,
	// Size desired by the widget
	desired_size: [2]f32,
}
// Animation
animate :: proc(value, duration: f32, condition: bool) -> f32 {
	value := value

	if condition {
		if value < 1 {
			core.draw_this_frame = true
			core.draw_next_frame = true
			value = min(1, value + core.delta_time * (1 / duration))
		}
	} else if value > 0 {
		core.draw_this_frame = true
		core.draw_next_frame = true
		value = max(0, value - core.delta_time * (1 / duration))
	}

	return value
}

// Set a widget's `variant` to type `T` and return a pointer to it
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

create_widget :: proc(id: Id) -> (widget: ^Widget, ok: bool) {
	for &slot in core.widgets {
		if slot == nil {
			slot = Widget {
				id = id,
			}
			widget = &slot.?
			// Add the new widget to the lookup map
			core.widget_map[id] = widget
			// A new widget was added and might be visible, so draw this frame
			core.draw_this_frame = true
			// The widget was successfully created so
			ok = true
			break
		}
	}
	return
}

get_widget :: proc(id: Id) -> (widget: ^Widget, ok: bool) {
	widget, ok = core.widget_map[id]
	if !ok {
		widget, ok = create_widget(id)
	}
	return
}

// Begins a new widget.
// This proc is way too long!
begin_widget :: proc(info: ^Widget_Info) -> bool {
	assert(info != nil)

	if info.self == nil {
		info.self = get_widget(info.id) or_return
	}

	widget := info.self

	// Place widget
	widget.box = info.box.? or_else next_widget_box(info)

	if widget.frames >= core.frames {
		draw_box_fill(
			widget.box,
			{
				255,
				0,
				0,
				u8(
					128.0 +
					math.sin(time.duration_seconds(time.since(core.start_time)) * 12.0) * 64.0,
				),
			},
		)
		return false
	}
	widget.frames = core.frames

	// Push to the stack
	push_stack(&core.widget_stack, widget) or_return

	// Widget must have a valid layer
	widget.layer = current_layer().? or_return

	// Keep alive
	widget.dead = false

	// Set visible flag
	widget.visible = core.visible && get_clip(current_scissor().?.box, widget.box) != .Full

	// Reset state
	widget.last_state = widget.state
	widget.state -= {.Clicked, .Focused, .Changed}

	// Disabled?
	widget.disabled = core.disable_widgets || info.disabled
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
			   time.since(widget.click_time) <= MAX_CLICK_DELAY {
				widget.click_count = max((widget.click_count + 1) % 4, 1)
			} else {
				widget.click_count = 1
			}
			widget.click_button = core.mouse_button
			widget.click_time = time.now()
			widget.state += {.Pressed}
			core.draw_this_frame = true
			// Set the globally dragged widget
			if info.sticky do core.dragged_widget = widget.id
		}
	} else if core.dragged_widget != widget.id  /* Keep hover and press state if dragged */{
		widget.state -= {.Pressed, .Hovered}
		widget.click_count = 0
	}
	// Mouse press
	if widget.state >= {.Pressed} {
		// Check for released buttons
		released_buttons := core.last_mouse_bits - core.mouse_bits
		for button in released_buttons {
			if button == widget.click_button {
				widget.state += {.Clicked}
				widget.state -= {.Pressed}
				break
			}
		}
	} else {
		// Reset click time if cursor is moved beyond a threshold
		if widget.click_count > 0 && linalg.length(core.mouse_pos - core.last_mouse_pos) > 2 {
			widget.click_count = 0
		}
	}
	// Focus state
	if core.focused_widget == widget.id {
		widget.state += {.Focused}
	}
	// Reset next state
	widget.state += widget.next_state
	widget.next_state = {}
	return true
}
// Ends the current widget
end_widget :: proc() {
	if widget, ok := current_widget().?; ok {
		if core.debug.enabled {
			draw_box_stroke(widget.box, 1, {0, 255, 0, 255})
		}
		if layout, ok := current_layout().?; ok {
			add_layout_content_size(
				layout,
				box_size(widget.box) if layout.fixed else widget.desired_size,
			)
		}
		pop_stack(&core.widget_stack)
	}
}
// Try make this widget hovered
hover_widget :: proc(widget: ^Widget) {
	// Disabled?
	if widget.disabled do return
	// Below highest hovered widget
	if widget.layer.index < core.highest_layer_index do return
	// Clipped?
	if clip, ok := current_scissor().?; ok && !point_in_box(core.mouse_pos, current_scissor().?.box) do return
	// Ok hover
	core.next_hovered_widget = widget.id
	core.next_hovered_layer = widget.layer.id
	core.highest_layer_index = widget.layer.index
}
// Try make this widget focused
focus_widget :: proc(widget: ^Widget) {
	core.focused_widget = widget.id
}

// Idk where else to put this, cause it's a generic widget
foreground :: proc(loc := #caller_location) {
	layout, ok := current_layout().?
	if !ok do return

	using info := Widget_Info {
		id  = hash(loc),
		box = layout.box,
	}
	if begin_widget(&info) {
		defer end_widget()

		draw_rounded_box_fill(info.self.box, core.style.rounding, core.style.color.foreground)
		// draw_rounded_box_stroke(info.self.box, core.style.rounding, 1, core.style.color.substance)

		if point_in_box(core.mouse_pos, info.self.box) {
			hover_widget(info.self)
		}
	}
}
