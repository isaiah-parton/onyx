package onyx

import "../vgo"
import "base:intrinsics"
import "base:runtime"
import "core:container/small_array"
import "core:fmt"
import "core:math"
import "core:math/ease"
import "core:math/linalg"
import "core:mem"
import "core:reflect"
import "core:strings"
import "core:time"
import "tedit"

MAX_CLICK_DELAY :: time.Millisecond * 450

Object_Flag :: enum {
	Is_Input,
	Persistent,
	Hover_Through,
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
	Dragged,
}

Object_Status_Set :: bit_set[Object_Status;u8]

OBJECT_STATE_ALL :: Object_Status_Set {
	.Hovered,
	.Focused,
	.Pressed,
	.Changed,
	.Clicked,
	.Open,
	.Active,
}

Object_Options :: struct {
	rounded_corners:  [4]f32,
	background_color: vgo.Color,
	disabled:         bool,
}

Object_Variant :: union {
	Button,
	Boolean,
	Container,
	Tab,
	Tabs,
	Input,
	Color_Picker,
	Date_Picker,
	Calendar,
	Calendar_Day,
}

Object :: struct {
	id:              Id,
	call_index:      int,
	frames:          int,
	size:            [2]f32,
	layer:           ^Layer,
	local_position:  [2]f32,
	box:             Box,
	dead:            bool,
	disabled:        bool,
	isolated:        bool,
	will_be_hovered: bool,
	flags:           Object_Flags,
	state:           Object_State,
	input:           Object_Input,
	variant:         Object_Variant,
}

Object_State :: struct {
	current:     Object_Status_Set,
	previous:    Object_Status_Set,
	input_mask:  Object_Status_Set,
	output_mask: Object_Status_Set,
}

Object_Content :: struct {
	side:          Side,
	justify:       Align,
	align:         Align,
	next_position: [2]f32,
	offset:        [2]f32,
	space_left:    [2]f32,
	size:          [2]f32,
	desired_size:  [2]f32,
	padding:       [4]f32,
	objects:       [dynamic]^Object,
}

Object_Metrics :: struct {
	size:         [2]f32,
	desired_size: [2]f32,
}

Object_Input :: struct {
	click_count:        int,
	click_release_time: time.Time,
	click_point:        [2]f32,
	click_mouse_button: Mouse_Button,
}

clean_up_objects :: proc() {
	for object, index in global_state.objects {
		if object.dead {
			destroy_object(object)
			delete_key(&global_state.object_map, object.id)
			ordered_remove(&global_state.objects, index)
			free(object)
			draw_frames(1)
		} else {
			object.dead = true
		}
	}
	small_array.clear(&global_state.transient_objects)
}

animate :: proc(value, duration: f32, condition: bool) -> f32 {
	value := value

	if condition {
		if value < 1 {
			draw_frames(2)
			value = min(1, value + global_state.delta_time * (1 / duration))
		}
	} else if value > 0 {
		draw_frames(2)
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

current_object :: proc() -> Maybe(^Object) {
	if global_state.object_stack.height > 0 {
		return global_state.object_stack.items[global_state.object_stack.height - 1]
	}
	return nil
}

last_object :: proc() -> Maybe(^Object) {
	return global_state.object_stack.items[global_state.object_stack.height]
}

new_persistent_object :: proc(id: Id) -> ^Object {
	object := new(Object)

	assert(object != nil)

	object.id = id
	object.state.output_mask = OBJECT_STATE_ALL

	append(&global_state.objects, object)
	global_state.object_map[id] = object

	draw_frames(1)

	return object
}

destroy_object :: proc(object: ^Object) {

}

make_object_children_array :: proc() -> [dynamic]^Object {
	return make_dynamic_array_len_cap([dynamic]^Object, 0, 16, allocator = context.temp_allocator)
}

persistent_object :: proc(id: Id) -> ^Object {
	object := global_state.object_map[id] or_else new_persistent_object(id)
	return object
}

make_transient_object :: proc() -> ^Object {
	small_array.append(&global_state.transient_objects, Object{})
	object :=
		small_array.get_ptr_safe(
			&global_state.transient_objects,
			global_state.transient_objects.len - 1,
		) or_else nil
	assert(object != nil)
	object.id = Id(global_state.transient_objects.len)
	object.state.output_mask = OBJECT_STATE_ALL

	return object
}

object_was_updated_this_frame :: proc(object: ^Object) -> bool {
	return object.frames >= global_state.frames
}

handle_object_click :: proc(object: ^Object, sticky: bool = false) {
	if global_state.hovered_object == object.id {
		object.state.current += {.Hovered}
		pressed_buttons := global_state.mouse_bits - global_state.last_mouse_bits
		if pressed_buttons != {} {
			if object.input.click_mouse_button == global_state.mouse_button &&
			   time.since(object.input.click_release_time) <= MAX_CLICK_DELAY {
				object.input.click_count = max((object.input.click_count + 1) % 4, 1)
			} else {
				object.input.click_count = 1
			}
			object.input.click_mouse_button = global_state.mouse_button
			object.input.click_point = global_state.mouse_pos
			object.input.click_release_time = time.now()
			object.state.current += {.Pressed}
			draw_frames(1)
			global_state.focused_object = object.id
			if sticky do global_state.dragged_object = object.id
		}
		// TODO: Lose click if mouse moved too much (allow for dragging containers by their contents)
		// if !info.sticky && linalg.length(core.click_mouse_pos - core.mouse_pos) > 8 {
		// 	object.state -= {.Pressed}
		// 	object.click_count = 0
		// }
	} else if global_state.dragged_object != object.id {
		object.state.current -= {.Pressed, .Hovered}
		object.input.click_count = 0
	}
	if object.state.current >= {.Pressed} {
		released_buttons := global_state.last_mouse_bits - global_state.mouse_bits
		if object.input.click_mouse_button in released_buttons {
			object.state.current += {.Clicked}
			object.state.current -= {.Pressed, .Dragged}
			global_state.dragged_object = 0
		}
	} else {
		if object.input.click_count > 0 &&
		   linalg.length(global_state.mouse_pos - global_state.last_mouse_pos) > 2 {
			object.input.click_count = 0
		}
	}
}

object_is_visible :: proc(object: ^Object) -> bool {
	return(
		global_state.visible &&
			get_clip(current_clip(), object.box) != .Full &&
			(object.box.lo.x < object.box.hi.x || object.box.lo.y < object.box.hi.y))
}

update_object_state :: proc(object: ^Object) {
	object.state.previous = object.state.current
	object.state.current -= {.Clicked, .Focused, .Changed, .Hovered}

	if global_state.focused_object == object.id {
		object.state.current += {.Focused}
	}
}

assign_next_object_index :: proc(object: ^Object) {
	object.call_index = global_state.object_index
	global_state.object_index += 1
}

begin_object :: proc(object: ^Object) -> bool {
	assert(object != nil)

	assign_next_object_index(object)

	object.dead = false

	if object_was_updated_this_frame(object) {
		when ODIN_DEBUG {
			fmt.printfln("Object ID collision: %i", object.id)
		}
		return false
	}
	object.frames = global_state.frames

	object.layer = current_layer().? or_return
	update_object_state(object)
	if global_state.disable_objects do object.disabled = true

	push_stack(&global_state.object_stack, object) or_return

	return true
}

end_object :: proc() {
	if object, ok := current_object().?; ok {
		transfer_object_state_to_its_layer(object)
		pop_stack(&global_state.object_stack)
		if parent, ok := current_object().?; ok {
			parent.state.current += object_state_output(object.state) & parent.state.input_mask
		}
	}
}

transfer_object_state_to_its_layer :: proc(object: ^Object) {
	object.layer.state += object.state.current
}

object_state_output :: proc(state: Object_State) -> Object_Status_Set {
	return state.current & state.output_mask
}

new_state :: proc(state: Object_State) -> Object_Status_Set {
	return state.current - state.previous
}

lost_state :: proc(state: Object_State) -> Object_Status_Set {
	return state.previous - state.current
}

hover_object :: proc(object: ^Object) {
	when DEBUG {
		if global_state.debug.enabled do return
	}
	if object.disabled do return
	if object.layer.index < global_state.hovered_layer_index do return
	if !point_in_box(global_state.mouse_pos, current_clip()) do return
	global_state.next_hovered_object = object.id
	global_state.next_hovered_layer = object.layer.id
	global_state.hovered_layer_index = object.layer.index
}

focus_object :: proc(object: ^Object) {
	global_state.focused_object = object.id
}

foreground :: proc(loc := #caller_location) {
	object := persistent_object(hash(loc))
	if begin_object(object) {
		defer end_object()
		object.state.input_mask = OBJECT_STATE_ALL
		draw_shadow(object.box)
		vgo.fill_box(object.box, paint = global_state.style.color.foreground)
		if point_in_box(global_state.mouse_pos, object.box) {
			hover_object(object)
		}
	}
}

background :: proc(loc := #caller_location) {
	object := persistent_object(hash(loc))
	if begin_object(object) {
		defer end_object()
		object.state.input_mask = OBJECT_STATE_ALL
		vgo.fill_box(object.box, paint = global_state.style.color.field)
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

draw_skeleton :: proc(box: Box, rounding: f32) {
	vgo.fill_box(box, rounding, global_state.style.color.substance)
	vgo.fill_box(box, rounding, vgo.Paint{kind = .Skeleton})

	draw_frames(1)
}

divider :: proc() {
	layout := current_layout().?
	vgo.fill_box(cut_box(&layout.box, current_options().side, 1), paint = colors().substance)
}

object_is_in_front_of :: proc(object: ^Object, other: ^Object) -> bool {
	if (object == nil) || (other == nil) do return true
	return (object.call_index > other.call_index) && (object.layer.index >= other.layer.index)
}

content_justify_causes_deference :: proc(justify: Align) -> bool {
	return int(justify) > 0
}

add_object_state_for_next_frame :: proc(object: ^Object, state: Object_Status_Set) {
	object.state.current += state
}
