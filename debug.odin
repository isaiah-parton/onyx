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
	t:  [Profiler_Scope]time.Time,
	d:  [Profiler_Scope]time.Duration,
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

print_object_debug_logs :: proc(object: ^Object) {
	new_state := object.state.current - object.state.previous
	old_state := object.state.previous - object.state.current
	if new_state > {} || old_state > {} {
		fmt.printf("[%8i] %x \t", global_state.frames, object.id)
		if new_state > {} {
			fmt.print("+{")
			i := 0
			for member in new_state {
				if i > 0 {
					fmt.print(", ")
				}
				i += 1
				fmt.print(member)
			}
			fmt.print("} ")
		}
		if old_state > {} {
			if new_state > {} {
				fmt.print("\n\t\t\t")
			}
			fmt.print("-{")
			i := 0
			for member in old_state {
				if i > 0 {
					fmt.print(", ")
				}
				i += 1
				fmt.print(member)
			}
			fmt.print("}")
		}
		fmt.print("\n")
	}
}

destroy_debug_state :: proc(state: ^Debug_State) {
	delete(state.hovered_objects)
}

@(private)
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
draw_object_debug_margin :: proc(box: Box, margin: [4]f32) {
	vgo.set_paint(vgo.fade(vgo.YELLOW, 0.5))
	if margin.x > 0 do vgo.fill_box(attach_box_left(box, margin.x))
	if margin.y > 0 do vgo.fill_box(attach_box_top(box, margin.y))
	if margin.z > 0 do vgo.fill_box(attach_box_right(box, margin.z))
	if margin.w > 0 do vgo.fill_box(attach_box_bottom(box, margin.w))
}

@(private)
draw_object_debug_padding :: proc(box: Box, padding: [4]f32) {
	box := box
	vgo.set_paint(vgo.fade(vgo.TURQUOISE, 0.5))
	if padding.x > 0 do vgo.fill_box(cut_box_left(&box, padding.x))
	if padding.y > 0 do vgo.fill_box(cut_box_top(&box, padding.y))
	if padding.z > 0 do vgo.fill_box(cut_box_right(&box, padding.z))
	if padding.w > 0 do vgo.fill_box(cut_box_bottom(&box, padding.w))
}

@(private)
draw_object_debug_box :: proc(state: Debug_State, object: ^Object) {
	if object_is_being_debugged(state, object) {
		vgo.fill_box(object.box, paint = vgo.fade(vgo.BLUE, 0.25))
	}
	vgo.stroke_box(object.box, 1, paint = vgo.BLUE)
}

@(private)
draw_object_debug_boxes :: proc(state: Debug_State) {
	for object in global_state.objects {
		draw_object_debug_box(state, object)
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
	}

	state.hovered_object_index += int(global_state.mouse_scroll.y)
	state.hovered_object_index = validate_debug_object_index(state^)

	if global_state.hovered_object != 0 {
		if object, ok := global_state.object_map[global_state.hovered_object]; ok {
			vgo.stroke_box(object.box, 1, paint = vgo.WHITE)
		}
	}

	if state.wireframe {
		vgo.reset_drawing()
		draw_object_debug_boxes(state^)
	} else {
		vgo.set_draw_order(1000)
	}

	DEBUG_TEXT_SIZE :: 14
	vgo.set_paint(vgo.WHITE)
	vgo.set_font(global_state.style.monospace_font)

	{
		total: time.Duration
		b := strings.builder_make(context.temp_allocator)
		fmt.sbprintf(&b, "FPS: %.0f", vgo.get_fps())
		for scope, s in Profiler_Scope {
			total += __prof.d[scope]
			fmt.sbprintf(&b, "\n%v: %.3fms", scope, time.duration_milliseconds(__prof.d[scope]))
			if scope == .Render {
				for timer in vgo.Debug_Timer {
					fmt.sbprintf(
						&b,
						"\n  %v: %.3fms",
						timer,
						time.duration_milliseconds(vgo.renderer().timers[timer]),
					)
				}
			}
		}
		fmt.sbprintf(&b, "\nTotal: %.3fms", time.duration_milliseconds(total))
		fmt.sbprintf(&b, "\nShapes: %i", len(vgo.renderer().shapes.data))
		fmt.sbprintf(&b, "\nPaints: %i", len(vgo.renderer().paints.data))
		fmt.sbprintf(&b, "\nMatrices: %i", len(vgo.renderer().xforms.data))
		fmt.sbprintf(&b, "\nControl Vertices: %i", len(vgo.renderer().cvs.data))
		fmt.sbprintf(&b, "\nDraw calls: %i", vgo.draw_call_count())
		fmt.sbprintf(&b, "\nObjects: %i", len(global_state.objects))
		fmt.sbprintf(&b, "\nLayers: %i", len(global_state.layer_array))
		fmt.sbprintf(&b, "\nPanels: %i", len(global_state.panel_map))
		vgo.fill_text(strings.to_string(b), DEBUG_TEXT_SIZE, 1, paint = vgo.BLACK)
		vgo.fill_text(strings.to_string(b), DEBUG_TEXT_SIZE, 0)
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
		vgo.fill_text_layout(text_layout, origin, align = {0, 1})
	}

	if object, ok := currently_debugged_object(state^); ok {
		b := strings.builder_make(context.temp_allocator)
		if !state.wireframe {
			draw_object_debug_box(state^, object)
		}
		fmt.sbprintf(
			&b,
			" index: %v\n id: %v\n box: [%.1f, %.1f]\n size: %.1f\n desired_size: %.1f\n content.size: %.1f\n content.desired_size: %.1f\n content.side: %v\n content.padding: %.2f",
			object.call_index + 1,
			object.id,
			object.box.lo,
			object.box.hi,
		)

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
		vgo.fill_box({origin, origin + header_text_layout.size}, paint = vgo.BLUE)
		vgo.fill_text_layout(header_text_layout, origin, paint = vgo.BLACK)
		vgo.fill_text_layout(
			info_text_layout,
			origin + {0, header_text_layout.size.y},
			paint = vgo.WHITE,
		)
	}
}
