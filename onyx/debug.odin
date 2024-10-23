package onyx

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
	offset: f32
	offset += draw_text({}, {
			text = fmt.tprintf(
`fps: %i

frames drawn: %i
draw calls:   %i

vertices: %i/%i
indices:  %i/%i
shapes:   %i/%i
paints:   %i/%i
cvs:      %i/%i
xforms:   %i/%i`,
core.frames_this_second,
core.drawn_frames,
len(core.draw_calls),
len(core.gfx.vertices),
(BUFFER_SIZE / size_of(Vertex)),
len(core.gfx.indices),
(BUFFER_SIZE / size_of(u32)),
len(core.gfx.shapes.data),
core.gfx.shapes.capacity,
len(core.gfx.paints.data),
core.gfx.shapes.capacity,
len(core.gfx.cvs.data),
core.gfx.cvs.capacity,
len(core.gfx.xforms.data),
core.gfx.xforms.capacity,
),
			font = core.style.monospace_font,
			size = 16,
		}, {255, 255, 255, 255}).y + 10
	for id, layer in core.layer_map {
		offset +=
			draw_text({0, f32(offset)}, {text = fmt.tprintf("%i - %i", layer.id, layer.index), font = core.style.monospace_font, size = 16}, 255).y
	}

	total: time.Duration
	for scope, s in Profiler_Scope {
		total += __prof.d[scope]
		draw_text(
			{0, core.view.y - f32(16 * (s + 1))},
			{
				text = fmt.tprintf(
					"%v: %.3fms",
					scope,
					time.duration_milliseconds(__prof.d[scope]),
				),
				font = core.style.monospace_font,
				size = 16,
				align_v = .Bottom,
			},
			{225, 225, 225, 255},
		)
	}
	draw_text(
		{0, core.view.y},
		{
			text = fmt.tprintf(
				"Total: %.3fms",
				time.duration_milliseconds(total),
			),
			font = core.style.monospace_font,
			size = 16,
			align_v = .Bottom,
		},
		{255, 255, 255, 255},
	)
}
