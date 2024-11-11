package onyx

import "../vgo"
import "core:fmt"
import "core:reflect"
import "core:time"

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
	enabled:          bool,
	delta_time:       [dynamic]f32,
	deferred_objects: int,
	hovered_object:   Maybe(^Object),
	wireframe:        bool,
}

@(private = "file")
__prof: Profiler

@(deferred_in = __profiler_scope)
profiler_scope :: proc(scope: Profiler_Scope) {
	profiler_begin_scope(scope)
}
__profiler_scope :: proc(scope: Profiler_Scope) {
	profiler_end_scope(scope)
}

profiler_begin_scope :: proc(scope: Profiler_Scope) {
	__prof.t[scope] = time.now()
}
profiler_end_scope :: proc(scope: Profiler_Scope) {
	__prof.d[scope] = time.since(__prof.t[scope])
}

draw_object_debug_boxes :: proc() {
	for _, object in global_state.object_map {
		vgo.stroke_box(object.box, 1, paint = vgo.GREEN)
	}
	for &object in global_state.transient_objects.data[:global_state.transient_objects.len] {
		vgo.stroke_box(object.box, 1, paint = vgo.BLUE)
	}
}

@(private)
draw_debug_stuff :: proc() {

	if global_state.debug.wireframe {
		vgo.reset_drawing()
		draw_object_debug_boxes()
	}

	DEBUG_TEXT_SIZE :: 16
	vgo.set_paint(vgo.WHITE)

	print_layer_debug :: proc(layer: ^Layer, left, pos: f32) -> f32 {
		pos := pos
		for child in layer.children {
			pos += print_layer_debug(child, left + 20, pos)
		}
		pos +=
			vgo.fill_text(fmt.tprintf("%i - %v %i", layer.id, layer.kind, layer.index), global_state.style.monospace_font, DEBUG_TEXT_SIZE, {left, pos}, paint = vgo.GOLD if layer.index == global_state.highest_layer_index else nil).y
		return pos
	}

	{
		total: time.Duration
		offset := f32(0)
		offset +=
			vgo.fill_text(fmt.tprintf("FPS: %.0f", vgo.get_fps()), global_state.style.monospace_font, DEBUG_TEXT_SIZE, {0, offset}).y
		for scope, s in Profiler_Scope {
			total += __prof.d[scope]
			offset +=
				vgo.fill_text(fmt.tprintf("%v: %.3fms", scope, time.duration_milliseconds(__prof.d[scope])), global_state.style.monospace_font, DEBUG_TEXT_SIZE, {0, offset}).y
		}
		offset +=
			vgo.fill_text(fmt.tprintf("Total: %.3fms", time.duration_milliseconds(total)), global_state.style.monospace_font, DEBUG_TEXT_SIZE, {0, offset}).y
		for layer in global_state.layers {
			offset += print_layer_debug(layer, 0, offset)
		}
	}

	vgo.fill_text_aligned(
		fmt.tprintf(
			"F6 = Turn %s FPS cap\nF7 = Toggle wireframes",
			"on" if global_state.disable_frame_skip else "off",
		),
		global_state.style.monospace_font,
		DEBUG_TEXT_SIZE,
		{0, global_state.view.y},
		.Left,
		.Bottom,
	)
}
