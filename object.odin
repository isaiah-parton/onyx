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
	Hover_Through,
	Sticky_Press,
	Sticky_Hover,
	No_Tab_Cycle,
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
	Color_Picker,
	Date_Picker,
	Calendar,
	Graph,
	Range_Slider,
	Slider,
}

Object :: struct {
	id:              Id,
	call_index:      int,
	frames:          int,
	size:            [2]f32,
	layer:           ^Layer,
	box:             Box,
	dead:            bool,
	disabled:        bool,
	isolated:        bool,
	will_be_hovered: bool,
	flags:           Object_Flags,
	state:           Object_State,
	click:           Object_Click,
	input:           Input_State,
	variant:         Object_Variant,
	hovered_time:    time.Time,
	hover_time:      f32,
	press_time:      f32,
}

Object_State :: struct {
	current:     Object_Status_Set,
	next:        Object_Status_Set,
	previous:    Object_Status_Set,
	input_mask:  Object_Status_Set,
	output_mask: Object_Status_Set,
}

Object_Click :: struct {
	count:        int,
	release_time: time.Time,
	press_time:   time.Time,
	point:        [2]f32,
	button:       Mouse_Button,
	mods: Mod_Keys,
}

Mod_Key :: enum {
	Control,
	Alt,
	Shift,
}
Mod_Keys :: bit_set[Mod_Key]

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
	if global_state.dragged_object != 0 {
		global_state.next_hovered_object = global_state.dragged_object
	}
	global_state.last_hovered_object = global_state.hovered_object
	global_state.hovered_object = global_state.next_hovered_object
	global_state.next_hovered_object = 0

	if global_state.mouse_bits - global_state.last_mouse_bits != {} {
		global_state.next_focused_object = global_state.hovered_object
	}

	global_state.last_focused_object = global_state.focused_object
	global_state.focused_object = global_state.next_focused_object
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

new_object :: proc(id: Id) -> ^Object {
	object := new(Object)

	assert(object != nil)

	object.id = id
	object.state.output_mask = OBJECT_STATE_ALL

	append(&global_state.objects, object)
	global_state.object_map[id] = object

	draw_frames(1)

	when ODIN_DEBUG {

	}

	return object
}

destroy_object :: proc(object: ^Object) {
	destroy_input(&object.input)
}

make_object_children_array :: proc() -> [dynamic]^Object {
	return make_dynamic_array_len_cap([dynamic]^Object, 0, 16, allocator = context.temp_allocator)
}

get_object :: proc(id: Id) -> ^Object {
	object := global_state.object_map[id] or_else new_object(id)
	return object
}

object_was_updated_this_frame :: proc(object: ^Object) -> bool {
	return object.frames >= global_state.frames
}

object_is_visible :: proc(object: ^Object) -> bool {
	return(
		global_state.visible &&
		get_clip(current_clip(), object.box) != .Full &&
		(object.box.lo.x < object.box.hi.x || object.box.lo.y < object.box.hi.y) \
	)
}

update_object_state :: proc(object: ^Object) {
	object.state.previous = object.state.current
	object.state.current -= {.Dragged, .Clicked, .Focused, .Changed, .Hovered}
	object.state.current += object.state.next
	object.state.next = {}

	if global_state.focused_object == object.id {
		object.state.current += {.Focused}
	}

	if id, ok := global_state.object_to_activate.?; ok {
		if id == object.id {
			object.state.current += {.Active}
			global_state.last_activated_object = object.id
		} else {
			object.state.current -= {.Active}
		}
	}

	if global_state.hovered_object == object.id {
		if current_options().hover_to_focus {
			if .Pressed not_in object.state.current {
				object.click.press_time = time.now()
				global_state.next_focused_object = object.id
			}
			object.state.current += {.Pressed}
			object.click.count = max(object.click.count, 1)
		}

		if .Hovered not_in object.state.previous {
			object.hovered_time = time.now()
		}

		object.state.current += {.Hovered}

		pressed_buttons := global_state.mouse_bits - global_state.last_mouse_bits
		if pressed_buttons != {} {
			if object.click.button == global_state.mouse_button &&
			   time.since(object.click.release_time) <= MAX_CLICK_DELAY {
				object.click.count = max((object.click.count + 1) % 4, 1)
			} else {
				object.click.count = 1
			}

			object.click.mods = {}
			if key_down(.Left_Control) || key_down(.Right_Control) {
				object.click.mods += {.Control}
			}
			if key_down(.Right_Shift) || key_down(.Left_Shift) {
				object.click.mods += {.Shift}
			}
			if key_down(.Left_Alt) || key_down(.Right_Alt) {
				object.click.mods += {.Alt}
			}

			object.click.button = global_state.mouse_button
			object.click.point = global_state.mouse_pos
			object.click.press_time = time.now()

			object.state.current += {.Pressed}
			if .Sticky_Hover in object.flags {
				global_state.dragged_object = object.id
			}
			global_state.next_focused_object = object.id

			draw_frames(1)
		}
		// TODO: Lose click if mouse moved too much (allow for dragging containers by their contents)
		// if !info.sticky && linalg.length(core.click_mouse_pos - core.mouse_pos) > 8 {
		// 	object.state -= {.Pressed}
		// 	object.click_count = 0
		// }
	} else {
		if global_state.dragged_object != object.id {
			object.state.current -= {.Hovered}
			object.click.count = 0
		}
		if .Sticky_Press not_in object.flags {
			object.state.current -= {.Pressed}
		}
	}

	if object.state.current >= {.Pressed} {
		released_buttons := global_state.last_mouse_bits - global_state.mouse_bits
		if released_buttons != {} {
			object.state.current += {.Clicked}
			object.state.current -= {.Pressed, .Dragged}
			object.click.release_time = time.now()
			global_state.dragged_object = 0
		}
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

	if global_state.focus_next {
		global_state.focus_next = false
		object.state.current += {.Active}
		global_state.next_focused_object = object.id
	}

	if global_state.disable_objects do object.disabled = true

	push_stack(&global_state.object_stack, object) or_return

	return true
}

end_object :: proc() {
	if object, ok := current_object().?; ok {
		when ODIN_DEBUG {
			// print_object_debug_logs(object)
			if .Focused in object.state.current {
				// vgo.stroke_box(object.box, 1, paint = vgo.BLUE)
			}
		}

		if .Active in (object.state.current - object.state.previous) {
			global_state.last_activated_object = object.id
		}

		if group, ok := current_group().?; ok {
			group.current_state += object.state.current
			group.previous_state += object.state.previous
		}

		object.layer.state += object.state.current

		pop_stack(&global_state.object_stack)

		if parent, ok := current_object().?; ok {
			parent.state.current += object_state_output(object.state) & parent.state.input_mask
		}
	}
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
	if object.disabled do return
	if object.layer.index < global_state.hovered_layer_index do return
	if !point_in_box(global_state.mouse_pos, current_clip()) do return
	global_state.next_hovered_object = object.id
	global_state.next_hovered_layer = object.layer.id
	global_state.hovered_layer_index = object.layer.index
}

focus_object :: proc(object: ^Object) {
	global_state.next_focused_object = object.id
}

foreground :: proc(loc := #caller_location) {
	object := get_object(hash(loc))
	object.box = current_box()
	if begin_object(object) {
		defer end_object()
		object.state.input_mask = OBJECT_STATE_ALL
		draw_shadow(object.box)
		vgo.fill_box(object.box, current_options().radius, paint = style().color.foreground)
		vgo.stroke_box(
			object.box,
			1,
			current_options().radius,
			paint = style().color.foreground_stroke,
		)
		if point_in_box(global_state.mouse_pos, object.box) {
			hover_object(object)
		}
	}
}

background :: proc(loc := #caller_location) {
	object := get_object(hash(loc))
	object.box = current_box()
	if begin_object(object) {
		defer end_object()
		object.state.input_mask = OBJECT_STATE_ALL
		vgo.fill_box(object.box, current_options().radius, paint = style().color.background)
		vgo.stroke_box(object.box, 1, current_options().radius, paint = style().color.foreground_stroke)
		if point_in_box(global_state.mouse_pos, object.box) {
			hover_object(object)
		}
	}
}

spinner :: proc(loc := #caller_location) {
	object := get_object(hash(loc))
	object.box = next_box({})
	if begin_object(object) {
		defer end_object()

		vgo.spinner(box_center(object.box), box_height(object.box) * 0.3, style().color.content)
		draw_frames(1)
	}
}

draw_skeleton :: proc(box: Box, rounding: f32) {
	vgo.fill_box(box, rounding, style().color.button)
	vgo.fill_box(box, rounding, vgo.Paint{kind = .Skeleton})

	draw_frames(1)
}

divider :: proc() {
	layout := current_layout().?
	side := current_options().side
	line_box := cut_box(&layout.box, side, 1)
	j := 1 - int(side) / 2
	line_box.lo[j] = layout.bounds.lo[j]
	line_box.hi[j] = layout.bounds.hi[j]
	vgo.fill_box(line_box, paint = style().color.foreground_stroke)
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
