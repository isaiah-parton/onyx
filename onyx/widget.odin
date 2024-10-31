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

// Widget variants
// 	I'm using a union for safety, idk if it's really necessary
//
// **TODO: Remove this**
Widget_Kind :: union {
	Menu_State,
	Graph_Widget_Kind,
	Tabs_Widget_Kind,
	Boolean_Widget_Kind,
	Date_Picker_Widget_Kind,
	Table_Widget_Kind,
	Color_Conversion_Widget_Kind,
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
	// TODO: Remove this
	variant:            Widget_Kind,
	// Generic state used by most widgets
	focus_time:         f32,
	hover_time:         f32,
	open_time:          f32,
	disable_time:       f32,
	// Unique state used by different widget types
	using unique_state: struct #raw_union {
		cont:    Container,
		menu:    Menu_State,
		graph:   Graph_Widget_Kind,
		tabs:    Tabs_Widget_Kind,
		input:   Input_State,
		boolean: Boolean_Widget_Kind,
		date:    Date_Picker_Widget_Kind,
		table:   Table_Widget_Kind,
		slider:  Slider_State,
	},
}

// A generic descriptor for all widgets
Widget_Info :: struct {
	self:           ^Widget,
	id:             Id,
	// Optional box to be used instead of cutting from the layout
	box:            Maybe(Box),
	// Can not receive input if true
	disabled:       bool,
	// If the mouse sticks to the widget
	sticky:         bool,
	// Which widget states can be passed to this widget
	in_state_mask:  Maybe(Widget_State),
	// Which widget states will be passed to the parent widget
	out_state_mask: Maybe(Widget_State),
	// Forces widget to occupy no more than its desired space
	fixed_size:     bool,
	// Size required by the user
	// required_size: [2]f32,
	// Size desired by the widget
	desired_size:   [2]f32,
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

	if (core.mouse_bits - core.last_mouse_bits) > {} {
		core.focused_widget = core.hovered_widget
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

destroy_widget :: proc(self: ^Widget) {
	if .Is_Input in self.flags {
		tedit.destroy_editor(&self.input.editor)
		strings.builder_destroy(&self.input.builder)
	}
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
	widget.box = snapped_box(move_box(info.box.? or_else next_widget_box(info), widget.offset))

	if widget.frames >= core.frames {
		vgo.fill_box(
			widget.box,
			paint = vgo.Color{
				0 = 255,
				3 = u8(
					128.0 +
					math.sin(time.duration_seconds(time.since(core.start_time)) * 12.0) * 64.0,
				),
			},
		)
		when ODIN_DEBUG {
			fmt.printfln("Widget ID collision: %i", info.id)
		}
		return false
	}
	widget.frames = core.frames
	// Push to the stack
	push_stack(&core.widget_stack, widget) or_return
	// Widget must have a valid layer
	widget.layer = current_layer().? or_return
	// TODO: Make this better
	widget.in_state_mask = info.in_state_mask.? or_else {}
	widget.out_state_mask = info.out_state_mask.? or_else WIDGET_STATE_ALL
	// Keep alive
	widget.dead = false
	// Set visible flag
	widget.visible = core.visible && get_clip(widget.layer.box, widget.box) != .Full
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
				widget.click_offset = core.mouse_pos - widget.box.lo
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
			core.focused_widget = widget.id
			// Set the globally dragged widget
			if info.sticky do core.dragged_widget = widget.id
		}
		// TODO: Lose click if mouse moved too much (allow for dragging containers by their contents)
		// if !info.sticky && linalg.length(core.click_mouse_pos - core.mouse_pos) > 8 {
		// 	widget.state -= {.Pressed}
		// 	widget.click_count = 0
		// }
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
				core.dragged_widget = 0
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
	// Update form
	if core.form_active {
		if core.form.first == nil {
			core.form.first = widget
		}
		if core.form.last != nil {
			widget.prev = core.form.last
			core.form.last.next = widget
		}
		core.form.last = widget
	}
	// Reset next state
	widget.state += widget.next_state
	widget.next_state = {}
	return true
}
// Ends the current widget
end_widget :: proc() {
	if widget, ok := current_widget().?; ok {
		// Draw debug box
		when ODIN_DEBUG {
			if core.debug.enabled {
				vgo.stroke_box(widget.box, 1, paint = vgo.GREEN)
			}
		}
		// Transfer state to layer
		{
			assert(widget.layer != nil)
			widget.layer.state += widget.state
		}
		// Update layout
		if layout, ok := current_layout().?; ok {
			add_layout_content_size(
				layout,
				box_size(widget.box) if layout.fixed else widget.desired_size,
			)
		}
		// Pop the stack
		pop_stack(&core.widget_stack)
		// Transfer state to parent
		if last_widget, ok := current_widget().?; ok {
			state_mask := widget.out_state_mask & last_widget.in_state_mask
			if .Pressed in widget.state && widget.id == core.dragged_widget {
				state_mask -= {.Pressed}
			}
			last_widget.next_state += widget.state & state_mask
		}
	}
}
// Try make this widget hovered
hover_widget :: proc(widget: ^Widget) {
	// Disabled?
	if widget.disabled do return
	// Below highest hovered widget
	if widget.layer.index < core.highest_layer_index do return
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
	info := Widget_Info {
		id            = hash(loc),
		box           = layout.box,
		in_state_mask = WIDGET_STATE_ALL,
	}
	if begin_widget(&info) {
		defer end_widget()
		vgo.fill_box(info.self.box, core.style.rounding, vgo.make_linear_gradient(
			info.self.box.lo,
			info.self.box.hi,
			vgo.blend(core.style.color.foreground, vgo.WHITE, 0.01),
			core.style.color.foreground,
		))
		if point_in_box(core.mouse_pos, info.self.box) {
			hover_widget(info.self)
		}
	}
}

background :: proc(loc := #caller_location) {
	layout, ok := current_layout().?
	if !ok do return
	info := Widget_Info {
		id            = hash(loc),
		box           = layout.box,
		in_state_mask = WIDGET_STATE_ALL,
	}
	if begin_widget(&info) {
		defer end_widget()
		vgo.fill_box(info.self.box, core.style.rounding, core.style.color.background)
		if point_in_box(core.mouse_pos, info.self.box) {
			hover_widget(info.self)
		}
	}
}

Spinner_Info :: Widget_Info

init_spinner :: proc(using info: ^Spinner_Info, loc := #caller_location) -> bool {
	if id == 0 do id = hash(loc)
	self = get_widget(id) or_return
	desired_size = core.style.visual_size.y
	return true
}

add_spinner :: proc(using info: ^Spinner_Info) -> bool {
	begin_widget(info) or_return
	defer end_widget()

	vgo.spinner(box_center(self.box), box_height(self.box) * 0.5, core.style.color.substance)

	return true
}

spinner :: proc(info: Spinner_Info, loc := #caller_location) -> Spinner_Info {
	info := info
	if init_spinner(&info) {
		add_spinner(&info)
	}
	return info
}

skeleton :: proc(loc := #caller_location) {
	info := Widget_Info {
		id = hash(loc),
	}
	if begin_widget(&info) {
		defer end_widget()
		draw_skeleton(info.self.box, core.style.rounding)
	}
}

draw_skeleton :: proc(box: Box, rounding: f32) {
	vgo.fill_box(box, rounding, core.style.color.substance)
	vgo.fill_box(box, rounding, vgo.Paint{kind = .Skeleton})

	core.draw_this_frame = true
}
