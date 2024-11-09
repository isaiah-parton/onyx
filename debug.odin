package onyx

import "../vgo"
import "core:fmt"
import "core:time"
import "core:reflect"

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
	enabled, objects, panels, layers: bool,
	delta_time:                       [dynamic]f32,
	deferred_objects:                 int,
	hovered_object: Maybe(^Object),
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

@(private)
do_debug_layer :: proc() {
	DEBUG_TEXT_SIZE :: 16
	vgo.set_paint(vgo.WHITE)

	print_layer_debug :: proc(layer: ^Layer, left, pos: f32) -> f32 {
		pos := pos
		for child in layer.children {
			pos += print_layer_debug(child, left + 20, pos)
		}
		pos +=
			vgo.fill_text_aligned(fmt.tprintf("%i - %v %i", layer.id, layer.kind, layer.index), global_state.style.monospace_font, DEBUG_TEXT_SIZE, {left, global_state.view.y - pos}, .Left, .Bottom, paint = vgo.GOLD if layer.index == global_state.highest_layer_index else nil).y
		return pos
	}

	// Layers
	{
		pos := f32(0)
		for layer in global_state.layers {
			pos += print_layer_debug(layer, 0, pos)
		}
	}

	// Timings
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
	}

	if object, ok := global_state.debug.hovered_object.?; ok {
		if layout, ok := object.variant.(Layout); ok {
			vgo.fill_text_aligned(
				fmt.tprintf("Layout:\naxis: %v\nbox: %.2f, %.2f", layout.axis, layout.box.lo, layout.box.hi),
				global_state.style.monospace_font,
				DEBUG_TEXT_SIZE,
				{0, global_state.view.y / 2},
				.Left,
				.Center,
			)
		}
	}
	global_state.debug.hovered_object = nil
}
