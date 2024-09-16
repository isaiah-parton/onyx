package onyx

import "core:fmt"

@(private)
do_debug_layer :: proc() {
	begin_layer({box = view_box(), sorting = .Above, kind = .Debug, options = {.Ghost}})
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
		color_from(0x5cf968ff),
	)
	end_layer()
}
