package onyx

import "../vgo"
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

MAX_CLICK_DELAY :: time.Millisecond * 450

Object_Flag :: enum {
	Is_Input,
	Persistent,
}

Object_Flags :: bit_set[Object_Flag;u8]

Object_Status :: enum {
	Hovered,
	Focused,
	Pressed,
	Changed,
	Clicked,
	Open,
	Active,
}

Object_State :: bit_set[Object_Status;u8]

OBJECT_STATE_ALL :: Object_State{.Hovered, .Focused, .Pressed, .Changed, .Clicked, .Open, .Active}

Object_Variant :: union {
	Button,
	Boolean,
	Container,
	Layout,
	Label,
}

Object :: struct {
	id:             Id,
	box:            Box,
	layer:          ^Layer,
	frames:         int,
	visible:        bool,
	disabled:       bool,
	dead:           bool,
	fixed:          bool,
	flags:          Object_Flags,
	last_state:     Object_State,
	next_state:     Object_State,
	state:          Object_State,
	in_state_mask:  Object_State,
	out_state_mask: Object_State,
	click_count:    int,
	click_time:     time.Time,
	click_point:    [2]f32,
	click_button:   Mouse_Button,
	desired_size:   [2]f32,
	margin:         Object_Margin,
	variant:        Object_Variant,
}

Object_Input :: struct {}

Object_Margin :: struct {
	left, right, top, bottom: f32,
}

Object_Placement :: struct {
	size:   [2]f32,
	margin: Object_Margin,
}

clean_up_objects :: proc() {
	for object, index in global_state.objects {
		if object.dead {
			destroy_object(object)
			delete_key(&global_state.object_map, object.id)
			ordered_remove(&global_state.objects, index)
			free(object)
			global_state.draw_this_frame = true
		} else {
			object.dead = true
		}
	}
	clear(&global_state.transient_objects)
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

update_object_references :: proc() {
	global_state.last_focused_object = global_state.focused_object
	global_state.last_hovered_object = global_state.hovered_object

	if global_state.dragged_object != 0 {
		global_state.hovered_object = global_state.dragged_object
	} else {
		global_state.hovered_object = global_state.next_hovered_object
	}

	global_state.next_hovered_object = 0

	if (global_state.mouse_bits - global_state.last_mouse_bits) > {} {
		global_state.focused_object = global_state.hovered_object
	}
}

enable_objects :: proc(enabled: bool = true) {
	global_state.disable_objects = !enabled
}

current_object :: proc() -> Maybe(^Object) {
	if global_state.object_stack.height > 0 {
		return global_state.object_stack.items[global_state.object_stack.height - 1]
	}
	return nil
}

new_persistent_object :: proc(id: Id) -> ^Object {
	object := new(Object)
	object.id = id
	object.out_state_mask = OBJECT_STATE_ALL
	global_state.object_map[id] = object
	global_state.draw_this_frame = true
	assert(object != nil)
	return object
}

destroy_object :: proc(object: ^Object) {

}

persistent_object :: proc(id: Id) -> ^Object {
	return global_state.object_map[id] or_else new_persistent_object(id)
}

transient_object :: proc() -> ^Object {
	append(&global_state.transient_objects, Object{})
	object := &global_state.transient_objects[len(global_state.transient_objects) - 1]
	assert(object != nil)
	return object
}

object_was_updated_this_frame :: proc(object: ^Object) -> bool {
	return object.frames >= global_state.frames
}

handle_object_click :: proc(object: ^Object, sticky: bool = false) {
	if global_state.hovered_object == object.id {
		// Add hovered state
		object.state += {.Hovered}
		// Clicking
		pressed_buttons := global_state.mouse_bits - global_state.last_mouse_bits
		if pressed_buttons != {} {
			if object.click_button == global_state.mouse_button &&
			   time.since(object.click_time) <= MAX_CLICK_DELAY {
				object.click_count = max((object.click_count + 1) % 4, 1)
			} else {
				object.click_count = 1
			}
			object.click_button = global_state.mouse_button
			object.click_point = global_state.mouse_pos
			object.click_time = time.now()
			object.state += {.Pressed}
			global_state.draw_this_frame = true
			global_state.focused_object = object.id
			// Set the globally dragged object
			if sticky do global_state.dragged_object = object.id
		}
		// TODO: Lose click if mouse moved too much (allow for dragging containers by their contents)
		// if !info.sticky && linalg.length(core.click_mouse_pos - core.mouse_pos) > 8 {
		// 	object.state -= {.Pressed}
		// 	object.click_count = 0
		// }
	} else if global_state.dragged_object !=
	   object.id  /* Keep hover and press state if dragged */{
		object.state -= {.Pressed, .Hovered}
		object.click_count = 0
	}
	// Mouse press
	if object.state >= {.Pressed} {
		// Check for released buttons
		released_buttons := global_state.last_mouse_bits - global_state.mouse_bits
		if global_state.mouse_button in released_buttons {
			object.state += {.Clicked}
			object.state -= {.Pressed}
			global_state.dragged_object = 0
		}
	} else {
		// Reset click time if cursor is moved beyond a threshold
		if object.click_count > 0 &&
		   linalg.length(global_state.mouse_pos - global_state.last_mouse_pos) > 2 {
			object.click_count = 0
		}
	}
}

begin_object :: proc(object: ^Object) -> bool {
	if object == nil do return false

	object.dead = false

	if object_was_updated_this_frame(object) {
		vgo.fill_box(
			object.box,
			paint = vgo.Color {
				0 = 255,
				3 = u8(
					128.0 +
					math.sin(time.duration_seconds(time.since(global_state.start_time)) * 12.0) *
						64.0,
				),
			},
		)
		when ODIN_DEBUG {
			fmt.printfln("Object ID collision: %i", object.id)
		}
		return false
	}
	object.frames = global_state.frames

	// Push to the stack
	push_stack(&global_state.object_stack, object) or_return
	// Object must have a valid layer
	object.layer = current_layer().? or_return
	// Set visible flag
	object.visible = global_state.visible && get_clip(object.layer.box, object.box) != .Full
	// Reset state
	object.last_state = object.state
	object.state -= {.Clicked, .Focused, .Changed}
	// Disabled?
	if global_state.disable_objects do object.disabled = true
	// Compute next frame's layout
	layout := current_layout().?
	// If the user set an explicit size with either `set_width()` or `set_height()` the object's desired size should reflect that
	// The purpose of these checks is that `set_size_fill()` makes content shrink to accommodate scrollbars
	if layout.object_size.x == 0 || layout.object_size.x != box_width(layout.box) {
		object.desired_size.x = max(object.desired_size.x, layout.object_size.x)
	}
	if layout.object_size.y == 0 || layout.object_size.y != box_height(layout.box) {
		object.desired_size.y = max(object.desired_size.y, layout.object_size.y)
	}
	// Focus state
	if global_state.focused_object == object.id {
		object.state += {.Focused}
	}
	// Update form
	// if global_state.form_active {
	// 	if global_state.form.first == nil {
	// 		global_state.form.first = object
	// 	}
	// 	if global_state.form.last != nil {
	// 		object.prev = global_state.form.last
	// 		global_state.form.last.next = object
	// 	}
	// 	global_state.form.last = object
	// }
	// Reset next state
	object.state += object.next_state
	object.next_state = {}
	return true
}

end_object :: proc() {
	if object, ok := current_object().?; ok {
		// Draw debug box
		when ODIN_DEBUG {
			if global_state.debug.enabled {
				if vgo.disable_scissor() {
					vgo.stroke_box(object.box, 1, paint = vgo.GREEN)
				}
			}
		}
		// Transfer state to layer
		object.layer.state += object.state
		// Update layout
		if layout, ok := current_layout().?; ok {
			add_layout_content_size(
				layout,
				box_size(object.box) if object.fixed else object.desired_size,
			)
		}
		// Pop the stack
		pop_stack(&global_state.object_stack)
		// Transfer state to parent
		if parent, ok := current_object().?; ok {
			transfer_object_state_to_parent(object, parent)
		}
	}
}

transfer_object_state_to_parent :: proc(child: ^Object, parent: ^Object) {
	state_mask := child.out_state_mask & parent.in_state_mask
	if .Pressed in child.state && child.id == global_state.dragged_object {
		state_mask -= {.Pressed}
	}
	parent.next_state += child.state & state_mask
}

hover_object :: proc(object: ^Object) {
	if object.disabled do return
	if object.layer.index < global_state.hovered_layer_index do return
	if !point_in_box(global_state.mouse_pos, object.layer.box) do return
	global_state.next_hovered_object = object.id
	global_state.next_hovered_layer = object.layer.id
	global_state.hovered_layer_index = object.layer.index
}

focus_object :: proc(object: ^Object) {
	global_state.focused_object = object.id
}

foreground :: proc(loc := #caller_location) {
	layout, ok := current_layout().?
	if !ok do return
	object := persistent_object(hash(loc))
	if begin_object(object) {
		defer end_object()
		if object.variant == nil {
			object.in_state_mask = OBJECT_STATE_ALL
		}
		object.box = layout.box
		vgo.fill_box(object.box, global_state.style.rounding, paint = global_state.style.color.fg)
		if point_in_box(global_state.mouse_pos, object.box) {
			hover_object(object)
		}
	}
}

background :: proc(loc := #caller_location) {
	layout, ok := current_layout().?
	if !ok do return
	object := persistent_object(hash(loc))
	if begin_object(object) {
		defer end_object()
		if object.variant == nil {
			object.in_state_mask = OBJECT_STATE_ALL
		}
		object.box = layout.box
		vgo.fill_box(object.box, global_state.style.rounding, global_state.style.color.field)
		if point_in_box(global_state.mouse_pos, object.box) {
			hover_object(object)
		}
	}
}

spinner :: proc(loc := #caller_location) {
	object := persistent_object(hash(loc))
	if begin_object(object) {
		defer end_object()

		vgo.spinner(
			box_center(object.box),
			box_height(object.box) * 0.5,
			global_state.style.color.substance,
		)
	}
}

// skeleton :: proc(loc := #caller_location) {
// 	info := Object_Info {
// 		id = hash(loc),
// 	}
// 	if begin_object(&info) {
// 		defer end_object()
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
	vgo.fill_box(cut, paint = global_state.style.color.substance)
}

display_object :: proc(object: ^Object) {
	switch &v in object.variant {
	case Button:
		display_button(&v)
	case Boolean:
		display_boolean(&v)
	case Container:
	case Layout:
		display_layout(&v)
	case Label:
		display_label(&v)
	}
}
