package onyx

import "core:fmt"
import "core:time"

Profiler_Scope :: enum {
	New_Frame,
	Render_Prepare,
	Render_Draw,
	Render_Present,
}

Profiler :: struct {
	t: [Profiler_Scope]time.Time,
	d: [Profiler_Scope]time.Duration,
}

@(private = "file")
__prof: Profiler

@(deferred_in = __profiler_end_scope)
profiler_begin_scope :: proc(scope: Profiler_Scope) {
	__prof.t[scope] = time.now()
}
__profiler_end_scope :: proc(scope: Profiler_Scope) {
	__prof.d[scope] = time.since(__prof.t[scope])
}

@(private)
do_debug_layer :: proc() {
	begin_layer({box = view_box(), sorting = .Above, kind = .Debug})
	draw_text(
		{},
		{
			text = fmt.tprintf(
				"fps: %i\nframes drawn: %i\ndraw calls: %i",
				core.frames_this_second,
				core.drawn_frames,
				core.draw_call_count,
			),
			font = core.style.fonts[.Regular],
			size = 20,
		},
		{255, 255, 255, 255},
	)
	for scope, s in Profiler_Scope {
		draw_text(
			{0, core.view.y - f32(20 * (s + 1))},
			{
				text = fmt.tprintf(
					"%v: %.2fms",
					scope,
					time.duration_milliseconds(__prof.d[scope]),
				),
				font = core.style.fonts[.Regular],
				size = 20,
			},
			{255, 255, 255, 255},
		)
	}
	end_layer()
}
