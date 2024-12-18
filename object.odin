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

Object_Variant :: union {
	Button,
	Boolean,
	Container,
	Label,
	Tabs,
	Input,
	HSV_Wheel,
	Slider,
	Alpha_Slider,
	Color_Picker,
	Date_Picker,
	Calendar,
	Calendar_Day,
	Scrollbar,
}

Child_Placement_Options :: struct {
	size:   [2]Layout_Size,
	align:  Align,
	margin: [4]f32,
}

Future_Object_Placement :: union {
	Child_Placement_Options,
	Future_Box_Placement,
}

Object :: struct {
	id:            Id,
	call_index:    int,
	frames:        int,
	layer:         ^Layer,
	box:           Box,
	placement:     Object_Placement,
	clip_children: bool,
	dead:          bool,
	is_deferred:   bool,
	disabled:      bool,
	isolated:      bool,
	flags:         Object_Flags,
	state:         Object_State,
	input:         Object_Input,
	metrics:       Object_Metrics,
	content:       Object_Content,
	parent:        Maybe(^Object),
	children:      [dynamic]^Object,
	on_display:    proc(_: ^Object),
	variant:       Object_Variant,
}

Object_State :: struct {
	current:     Object_Status_Set,
	previous:    Object_Status_Set,
	input_mask:  Object_Status_Set,
	output_mask: Object_Status_Set,
}

Object_Content :: struct {
	axis:         Axis,
	side:         Side,
	justify:      Align,
	align:        Align,
	box:          Box,
	space_left:   [2]f32,
	size:         [2]f32,
	desired_size: [2]f32,
	padding:      [4]f32,
	objects:      [dynamic]^Object,
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

set_object_desired_size :: proc(object: ^Object, size: [2]f32) {
	object.metrics.desired_size = size
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
	delete(object.children)
	#partial switch &v in object.variant {
	case Input:
		destroy_input(&v)
	case:
		break
	}
}

make_object_children_array :: proc() -> [dynamic]^Object {
	return make_dynamic_array_len_cap([dynamic]^Object, 0, 16, allocator = context.temp_allocator)
}

persistent_object :: proc(id: Id) -> ^Object {
	object := global_state.object_map[id] or_else new_persistent_object(id)
	object.children = make_object_children_array()
	object.metrics.desired_size = 0
	return object
}

transient_object :: proc() -> ^Object {
	small_array.append(&global_state.transient_objects, Object{})
	object :=
		small_array.get_ptr_safe(
			&global_state.transient_objects,
			global_state.transient_objects.len - 1,
		) or_else nil
	assert(object != nil)
	object.id = Id(global_state.transient_objects.len)
	object.children = make_object_children_array()
	object.state.output_mask = OBJECT_STATE_ALL
	object.metrics.desired_size = 0
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
	return global_state.visible && get_clip(current_clip(), object.box) != .Full
}

update_object_state :: proc(object: ^Object) {
	object.state.previous = object.state.current
	object.state.current -= {.Clicked, .Focused, .Changed}

	if global_state.focused_object == object.id {
		object.state.current += {.Focused}
	}
}

begin_object :: proc(object: ^Object) -> bool {
	assert(object != nil)

	object.call_index = global_state.object_index
	global_state.object_index += 1

	object.dead = false

	if object_was_updated_this_frame(object) {
		when ODIN_DEBUG {
			fmt.printfln("Object ID collision: %i", object.id)
		}
		return false
	}
	object.frames = global_state.frames

	object.layer = current_layer().? or_return
	object.parent = current_object()
	update_object_state(object)
	if global_state.disable_objects do object.disabled = true

	if parent, ok := object.parent.?; ok {
		if object_defers_children(parent) {
			object.is_deferred = true
		}
	}

	switch v in object.placement {
	case nil:
		object.is_deferred = true
	case Future_Box_Placement:
		object.is_deferred = true
	case vgo.Box:
		object.is_deferred = false
	case Child_Placement_Options:
		if v.size[0] == nil || v.size[1] == nil {
			object.is_deferred = true
		}
	}

	object.content.size = 0
	object.content.desired_size = 0
	object.content.axis = axis_of_side(object.content.side)
	if !object.is_deferred {
		place_object(object) or_return
	}

	if object.clip_children {
		vgo.save_scissor()
		vgo.push_scissor(vgo.make_box(object.box))
		push_clip(object.box)
	}

	push_stack(&global_state.object_stack, object) or_return

	return true
}

end_object :: proc() {
	if object, ok := current_object().?; ok {

		object.layer.state += object.state.current

		if object.clip_children {
			pop_clip()
			vgo.restore_scissor()
		}

		pop_stack(&global_state.object_stack)

		object.metrics.desired_size = linalg.max(
			object.metrics.desired_size,
			space_required_by_object_content(object.content),
		)

		if parent, ok := object.parent.?; ok {
			update_object_parent_metrics(object)
			parent.state.current += object_state_output(object.state) & parent.state.input_mask
		}

		if !maybe_defer_object(object) {
			display_object(object)
		}
	}
}

space_required_by_object_content :: proc(content: Object_Content) -> [2]f32 {
	return content.desired_size + content.padding.xy + content.padding.zw
}

occupied_space_of_object :: proc(object: ^Object) -> [2]f32 {
	size := object.metrics.size
	if placement, ok := object.placement.(Child_Placement_Options); ok {
		size += placement.margin.xy + placement.margin.zw
	}
	return size
}

space_required_by_object :: proc(object: ^Object) -> [2]f32 {
	size := object.metrics.desired_size
	if placement, ok := object.placement.(Child_Placement_Options); ok {
		size += placement.margin.xy + placement.margin.zw
	}
	return size
}

total_space_for_object_content :: proc(object: ^Object) -> [2]f32 {
	return object.metrics.size - object.content.padding.xy - object.content.padding.zw
}

available_space_for_object_content :: proc(object: ^Object) -> [2]f32 {
	return box_size(object.content.box)
}

update_object_parent_metrics :: proc(object: ^Object) {
	// TODO: Put this somewhere else
	if object.isolated do return

	effective_desired_size := space_required_by_object(object)
	effective_size := occupied_space_of_object(object)

	parent := object.parent.?

	i := int(parent.content.axis)
	j := 1 - i

	parent.content.desired_size[i] += effective_desired_size[i]
	parent.content.desired_size[j] = max(parent.content.desired_size[j], effective_desired_size[j])

	parent.content.size[i] += effective_size[i]
	parent.content.size[j] = max(parent.content.size[j], effective_size[j])
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
		if object.on_display == nil {
			object.on_display = proc(object: ^Object) {
				object.box = object.parent.?.box
				draw_shadow(object.box)
				vgo.fill_box(object.box, global_state.style.rounding, global_state.style.color.fg)
				if point_in_box(global_state.mouse_pos, object.box) {
					hover_object(object)
				}
			}
		}
	}
}

background :: proc(loc := #caller_location) {
	object := persistent_object(hash(loc))
	if begin_object(object) {
		defer end_object()
		object.state.input_mask = OBJECT_STATE_ALL
		if object.on_display == nil {
			object.on_display = proc(object: ^Object) {
				object.box = object.parent.?.box
				vgo.fill_box(
					object.box,
					global_state.style.rounding,
					global_state.style.color.field,
				)
				if point_in_box(global_state.mouse_pos, object.box) {
					hover_object(object)
				}
			}
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

object_is_in_front_of :: proc(object: ^Object, other: ^Object) -> bool {
	if (object == nil) || (other == nil) do return true
	return (object.call_index > other.call_index) && (object.layer.index >= other.layer.index)
}

display_object :: proc(object: ^Object) {
	if object.is_deferred {
		place_object(object)
	}

	when DEBUG {
		if point_in_box(mouse_point(), object.box) {
			if object_is_in_front_of(object, top_hovered_object(global_state.debug) or_else nil) {
				global_state.debug.top_object_index = len(global_state.debug.hovered_objects)
			}
			append(&global_state.debug.hovered_objects, object)
		}
	}

	switch &v in object.variant {
	case Date_Picker:
		display_date_picker(&v)
	case Container:
		display_container(&v)
	case Input:
		display_input(&v)
	case Button:
		display_button(&v)
	case Boolean:
		display_boolean(&v)
	case Label:
		display_label(&v)
	case Slider:
		display_slider(&v)
	case HSV_Wheel:
		display_hsv_wheel(&v)
	case Alpha_Slider:
		display_alpha_slider(&v)
	case Color_Picker:
		display_color_picker(&v)
	case Tabs:
		display_tabs(&v)
	case Scrollbar:
		display_scrollbar(&v)
	case Calendar_Day:
		display_calendar_day(&v)
	case Calendar:
		break
	case nil:
		if object.on_display != nil {
			object.on_display(object)
		}
	}

	if object.clip_children {
		vgo.save_scissor()
		vgo.push_scissor(vgo.make_box(object.box))
		push_clip(object.box)
	}

	if content_justify_causes_deference(object.content.justify) {
		object.content.space_left = box_size(object.content.box)
		for child_object in object.children {
			if placement, ok := child_object.placement.(Child_Placement_Options); ok {
				child_object.metrics.size, child_object.metrics.desired_size = solve_child_object_size(
					placement.size,
					child_object.metrics.desired_size,
					available_space_for_object_content(object),
					total_space_for_object_content(object),
				)
				object.content.space_left -= occupied_space_of_object(child_object)
			}
		}
		object.content.space_left *= axis_normal(object.content.axis)
	}

	for child_object in object.children {
		display_object(child_object)
	}

	if object.clip_children {
		pop_clip()
		vgo.restore_scissor()
	}

	if parent, ok := object.parent.?; ok {
		parent.state.current += object_state_output(object.state) & parent.state.input_mask
	}
}

content_justify_causes_deference :: proc(justify: Align) -> bool {
	return int(justify) > 0
}
