package onyx

import "../../vgo"
import "core:fmt"
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

	{
		offset := f32(0)
		for _, &layer in core.layer_map {
			offset +=
				vgo.fill_text(fmt.tprintf("%i - %v %i", layer.id, layer.kind, layer.index), core.style.monospace_font, DEBUG_TEXT_SIZE, {0, offset}).y
		}
	}

	total: time.Duration
	vgo.fill_text_aligned(
		fmt.tprintf("FPS: %.0f", vgo.get_fps()),
		core.style.monospace_font,
		DEBUG_TEXT_SIZE,
		{0, core.view.y - f32(len(Profiler_Scope) + 1) * DEBUG_TEXT_SIZE},
		.Left,
		.Bottom,
	)
	for scope, s in Profiler_Scope {
		total += __prof.d[scope]
		vgo.fill_text_aligned(
			fmt.tprintf("%v: %.3fms", scope, time.duration_milliseconds(__prof.d[scope])),
			core.style.monospace_font,
			DEBUG_TEXT_SIZE,
			{0, core.view.y - f32(DEBUG_TEXT_SIZE * (s + 1))},
			.Left,
			.Bottom,
			paint = vgo.WHITE,
		)
	}
	vgo.fill_text_aligned(
		fmt.tprintf("Total: %.3fms", time.duration_milliseconds(total)),
		core.style.monospace_font,
		DEBUG_TEXT_SIZE,
		{0, core.view.y},
		.Left,
		.Bottom,
		paint = vgo.WHITE,
	)
}
