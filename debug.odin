package onyx

import "../vgo"
import "base:runtime"
import "core:fmt"
import "core:math/linalg"
import "core:reflect"
import "core:slice"
import "core:strings"
import "core:time"

DEBUG :: #config(ONYX_DEBUG, ODIN_DEBUG)

Profiler_Scope :: enum {
	New_Frame,
	Construct,
	Render,
}

Profiler :: struct {
	t: [Profiler_Scope]time.Time,
	d: [Profiler_Scope]time.Duration,
}

Debug_State :: struct {
	enabled:               bool,
	deferred_objects:      int,
	hovered_objects:       [dynamic]^Object,
	last_top_object_index: int,
	top_object_index:      int,
	hovered_object_index:  int,
	wireframe:             bool,
}

destroy_debug_state :: proc(state: ^Debug_State) {
	delete(state.hovered_objects)
}

@(private = "file")
__prof: Profiler

@(deferred_in = __profiler_scope)
@(private)
profiler_scope :: proc(scope: Profiler_Scope) {
	profiler_begin_scope(scope)
}

@(private)
__profiler_scope :: proc(scope: Profiler_Scope) {
	profiler_end_scope(scope)
}

@(private)
profiler_begin_scope :: proc(scope: Profiler_Scope) {
	__prof.t[scope] = time.now()
}

@(private)
profiler_end_scope :: proc(scope: Profiler_Scope) {
	__prof.d[scope] = time.since(__prof.t[scope])
}

@(private)
draw_object_debug_box :: proc(state: Debug_State, object: ^Object) {
	color := vgo.GREEN
	variant := reflect.union_variant_typeid(object.variant)
	if variant == Layout {
		color = vgo.BLUE
	}
	vgo.stroke_box(object.box, 1, paint = color)
	if object_is_being_debugged(state, object) {
		vgo.fill_box(object.box, paint = vgo.fade(color, 0.5))
		vgo.set_paint(vgo.fade(vgo.YELLOW, 0.5))
		if object.margin.x > 0 do vgo.fill_box(attach_box_left(object.box, object.margin.x))
		if object.margin.y > 0 do vgo.fill_box(attach_box_top(object.box, object.margin.y))
		if object.margin.z > 0 do vgo.fill_box(attach_box_right(object.box, object.margin.z))
		if object.margin.w > 0 do vgo.fill_box(attach_box_bottom(object.box, object.margin.w))
	}
}

@(private)
draw_object_debug_boxes :: proc(state: Debug_State) {
	for object in global_state.objects {
		draw_object_debug_box(state, object)
	}
	for &object in global_state.transient_objects.data[:global_state.transient_objects.len] {
		draw_object_debug_box(state, &object)
	}
}

@(private)
object_is_being_debugged :: proc(state: Debug_State, object: ^Object) -> bool {
	return(
		len(state.hovered_objects) > 0 &&
		object == state.hovered_objects[state.hovered_object_index] \
	)
}

@(private)
currently_debugged_object :: proc(state: Debug_State) -> (object: ^Object, ok: bool) {
	if len(state.hovered_objects) == 0 || len(state.hovered_objects) <= state.hovered_object_index do return
	return state.hovered_objects[state.hovered_object_index], true
}

@(private)
top_hovered_object :: proc(state: Debug_State) -> (object: ^Object, ok: bool) {
	if len(state.hovered_objects) == 0 || len(state.hovered_objects) <= state.top_object_index do return
	return state.hovered_objects[state.top_object_index], true
}

@(private)
validate_debug_object_index :: proc(state: Debug_State) -> int {
	return max(min(state.hovered_object_index, len(state.hovered_objects) - 1), 0)
}

@(private)
draw_debug_stuff :: proc(state: ^Debug_State) {

	if state.top_object_index != state.last_top_object_index {
		state.last_top_object_index = state.top_object_index
		state.hovered_object_index = state.top_object_index
		// slice.reverse_sort_by(state.hovered_objects[:], object_is_in_front_of)
	}

	state.hovered_object_index += int(global_state.mouse_scroll.y)
	state.hovered_object_index = validate_debug_object_index(state^)

	if state.wireframe {
		vgo.reset_drawing()
		draw_object_debug_boxes(state^)
	}

	DEBUG_TEXT_SIZE :: 16
	vgo.set_paint(vgo.WHITE)
	vgo.set_font(global_state.style.monospace_font)

	{
		total: time.Duration
		b := strings.builder_make(context.temp_allocator)
		fmt.sbprintf(&b, "FPS: %.0f", vgo.get_fps())
		for scope, s in Profiler_Scope {
			total += __prof.d[scope]
			fmt.sbprintf(&b, "\n%v: %.3fms", scope, time.duration_milliseconds(__prof.d[scope]))
		}
		fmt.sbprintf(&b, "\nTotal: %.3fms", time.duration_milliseconds(total))
		vgo.fill_text(strings.to_string(b), DEBUG_TEXT_SIZE, {})
	}

	{
		text_layout := vgo.make_text_layout(
			fmt.tprintf(
				"Scroll = Cycle objects\nF3 = Exit debug\nF6 = Turn %s FPS cap\nF7 = Toggle wireframes",
				"on" if global_state.disable_frame_skip else "off",
			),
			DEBUG_TEXT_SIZE,
			font = global_state.style.monospace_font,
		)
		origin := [2]f32{0, global_state.view.y}
		vgo.fill_text_layout(
			text_layout,
			origin + 2,
			align_x = .Left,
			align_y = .Bottom,
			paint = vgo.BLACK,
		)
		vgo.fill_text_layout(text_layout, origin, align_x = .Left, align_y = .Bottom)
	}
	if object, ok := currently_debugged_object(state^); ok {
		b := strings.builder_make(context.temp_allocator)
		if !state.wireframe {
			draw_object_debug_box(state^, object)
			if layout, ok := object.variant.(Layout); ok {
				for child in layout.objects {
					draw_object_debug_box(state^, child)
				}
			}
		}
		fmt.sbprintf(
			&b,
			" index: %v\n id: %v\n box: [%.1f, %.1f]\n size: %.1f\n desired_size: %.1f",
			object.index + 1,
			object.id,
			object.box.lo,
			object.box.hi,
			object.size,
			object.desired_size,
		)
		if layout, ok := object.variant.(Layout); ok {
			fmt.sbprintf(
				&b,
				"\n axis: %v\n justify: %v\n align: %v\n has_known_box: %v\n deferred: %v\n children: %i",
				layout.axis,
				layout.justify,
				layout.align,
				layout.has_known_box,
				layout_is_deferred(&layout),
				len(layout.objects),
			)
		}

		variant_typeid := reflect.union_variant_typeid(object.variant)
		header_text_layout := vgo.make_text_layout(
			fmt.tprintf(
				"%i/%i: %v",
				state.hovered_object_index + 1,
				len(state.hovered_objects),
				variant_typeid if variant_typeid != nil else typeid_of(Object),
			),
			DEBUG_TEXT_SIZE,
		)
		info_text_layout := vgo.make_text_layout(strings.to_string(b), DEBUG_TEXT_SIZE)
		size := info_text_layout.size + {0, header_text_layout.size.y}
		origin := linalg.clamp(mouse_point() + 10, 0, global_state.view - size)

		vgo.fill_box({origin, origin + size}, paint = vgo.fade(vgo.BLACK, 0.75))
		vgo.fill_box({origin, origin + header_text_layout.size}, paint = vgo.BLUE if variant_typeid == Layout else vgo.GREEN)
		vgo.fill_text_layout(header_text_layout, origin, paint = vgo.BLACK)
		vgo.fill_text_layout(
			info_text_layout,
			origin + {0, header_text_layout.size.y},
			paint = vgo.WHITE,
		)
	}
}
