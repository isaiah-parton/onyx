package ronin

import kn "local:katana"
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
	kn.set_paint(kn.fade(kn.Yellow, 0.5))
	if margin.x > 0 do kn.add_box(attach_box_left(box, margin.x))
	if margin.y > 0 do kn.add_box(attach_box_top(box, margin.y))
	if margin.z > 0 do kn.add_box(attach_box_right(box, margin.z))
	if margin.w > 0 do kn.add_box(attach_box_bottom(box, margin.w))
}

@(private)
draw_object_debug_padding :: proc(box: Box, padding: [4]f32) {
	box := box
	kn.set_paint(kn.fade(kn.Turquoise, 0.5))
	if padding.x > 0 do kn.add_box(cut_box_left(&box, padding.x))
	if padding.y > 0 do kn.add_box(cut_box_top(&box, padding.y))
	if padding.z > 0 do kn.add_box(cut_box_right(&box, padding.z))
	if padding.w > 0 do kn.add_box(cut_box_bottom(&box, padding.w))
}

@(private)
draw_object_debug_box :: proc(state: Debug_State, object: ^Object) {
	if object_is_being_debugged(state, object) {
		kn.add_box(object.box, paint = kn.fade(kn.Blue, 0.25))
	}
	kn.add_box_lines(object.box, 1, paint = kn.Blue)
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
			kn.add_box_lines(object.box, 1, paint = kn.White)
		}
	}

	if state.wireframe {
		kn.reset_drawing()
		draw_object_debug_boxes(state^)
	} else {
		kn.set_draw_order(1000)
	}

	DEBUG_TEXT_SIZE :: 14
	kn.set_paint(kn.White)
	kn.set_font(global_state.style.monospace_font)

	{
		total: time.Duration
		b := strings.builder_make(context.temp_allocator)
		fmt.sbprintf(&b, "FPS: %.0f", kn.get_fps())
		for scope, s in Profiler_Scope {
			total += __prof.d[scope]
			fmt.sbprintf(&b, "\n%v: %.3fms", scope, time.duration_milliseconds(__prof.d[scope]))
			if scope == .Render {
				for timer in kn.Debug_Timer {
					fmt.sbprintf(
						&b,
						"\n  %v: %.3fms",
						timer,
						time.duration_milliseconds(kn.renderer().timers[timer]),
					)
				}
			}
		}
		fmt.sbprintf(&b, "\nTotal: %.3fms", time.duration_milliseconds(total))
		fmt.sbprintf(&b, "\nShapes: %i", len(kn.renderer().shapes.data))
		fmt.sbprintf(&b, "\nPaints: %i", len(kn.renderer().paints.data))
		fmt.sbprintf(&b, "\nMatrices: %i", len(kn.renderer().xforms.data))
		fmt.sbprintf(&b, "\nControl Vertices: %i", len(kn.renderer().cvs.data))
		fmt.sbprintf(&b, "\nDraw calls: %i", kn.draw_call_count())
		fmt.sbprintf(&b, "\nObjects: %i", len(global_state.objects))
		fmt.sbprintf(&b, "\nLayers: %i", len(global_state.layer_array))
		fmt.sbprintf(&b, "\nPanels: %i", len(global_state.panel_map))
		kn.add_string(strings.to_string(b), DEBUG_TEXT_SIZE, 1, paint = kn.Black)
		kn.add_string(strings.to_string(b), DEBUG_TEXT_SIZE, 0)
	}

	{
		text_layout := kn.make_text(
			fmt.tprintf(
				"Scroll = Cycle objects\nF3 = Exit debug\nF6 = Turn %s FPS cap\nF7 = Toggle wireframes",
				"on" if global_state.disable_frame_skip else "off",
			),
			DEBUG_TEXT_SIZE,
			font = global_state.style.monospace_font,
		)
		origin := [2]f32{0, global_state.view.y}
		kn.add_text(text_layout, origin - text_layout.size * {0, 1})
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
		header_text_layout := kn.make_text(
			fmt.tprintf(
				"%i/%i: %v",
				state.hovered_object_index + 1,
				len(state.hovered_objects),
				variant_typeid if variant_typeid != nil else typeid_of(Object),
			),
			DEBUG_TEXT_SIZE,
		)
		info_text_layout := kn.make_text(strings.to_string(b), DEBUG_TEXT_SIZE)
		size := info_text_layout.size + {0, header_text_layout.size.y}
		origin := linalg.clamp(mouse_point() + 10, 0, global_state.view - size)

		kn.add_box({origin, origin + size}, paint = kn.fade(kn.Black, 0.75))
		kn.add_box({origin, origin + header_text_layout.size}, paint = kn.Blue)
		kn.add_text(header_text_layout, origin, paint = kn.Black)
		kn.add_text(
			info_text_layout,
			origin + {0, header_text_layout.size.y},
			paint = kn.White,
		)
	}
}
