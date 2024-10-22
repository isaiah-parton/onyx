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
	for scope, s in Profiler_Scope {
		draw_text(
			{0, core.view.y - f32(14 * (s + 1))},
			{
				text = fmt.tprintf(
					"%v: %.2fms",
					scope,
					time.duration_milliseconds(__prof.d[scope]),
				),
				font = core.style.default_font,
				size = 16,
			},
			{255, 255, 255, 255},
		)
	}
}
