package onyx

import "core:time"
import sdtx "extra:sokol-odin/sokol/debugtext"

Profiler :: struct {
	frame_times: [dynamic]f64,
}

update_profiler :: proc(p: ^Profiler, frame_time: f64, cap: int) {
	resize(&p.frame_times, cap)
	if len(p.frame_times) == 0 {
		return
	}
	copy(p.frame_times[:], p.frame_times[1:])
	p.frame_times[0] = frame_time
}

print_debug_text :: proc() {
	sdtx.canvas(core.view.x, core.view.y)

	sdtx.color3b(255, 255, 255)

	sdtx.printf("frame %i\n", core.frame_count)
	sdtx.color3b(170, 170, 170)
	sdtx.printf("\tui: %fms\n", time.duration_milliseconds(time.since(core.last_frame_time)))
	sdtx.printf("\trender: %fms\n", time.duration_milliseconds(core.render_duration))
	sdtx.printf("\tdraw calls: %i/%i\n", core.draw_call_count, MAX_DRAW_CALLS)
	sdtx.printf("\tvertices: %i/%i\n", len(core.draw_list.vertices), MAX_VERTICES)
	sdtx.printf("\ttris: %i\n", len(core.draw_list.indices) / 3)
	sdtx.color3b(255, 255, 255)

	sdtx.move_y(1)

	sdtx.printf("%c Layers (L)\n", '-' if core.debug.layers else '+')
	if key_pressed(.L) do core.debug.layers = !core.debug.layers
	if core.debug.layers {
		sdtx.color3b(170, 170, 170)
		__debug_print_layer :: proc(layer: ^Layer, depth: int = 0) {
			sdtx.putc('H' if .Hovered in layer.state else '_')
			sdtx.putc('F' if .Focused in layer.state else '_')
			for i in 0 ..< depth {
				sdtx.putc('\t')
			}
			sdtx.printf("\t{:i} ({}) ({})\n", layer.id, layer.kind, layer.index)
			for child in layer.children {
				__debug_print_layer(child, depth + 1)
			}
		}
		for _, layer in core.layer_map {
			if layer.parent == nil {
				__debug_print_layer(layer, 0)
			}
		}
		sdtx.color3b(255, 255, 255)
	}

	sdtx.move_y(1)

	sdtx.printf("%c Widgets (W)\n", '-' if core.debug.widgets else '+')
	if key_pressed(.W) do core.debug.widgets = !core.debug.widgets
	if core.debug.widgets {
		sdtx.color3b(170, 170, 170)
		for id, &widget in core.widget_map {
			sdtx.putc('H' if .Hovered in widget.state else '_')
			sdtx.putc('F' if .Focused in widget.state else '_')
			sdtx.putc('P' if .Pressed in widget.state else '_')
			sdtx.printf(" {:i}\n", widget.id)
		}
		sdtx.color3b(255, 255, 255)
	}

	sdtx.move_y(1)

	sdtx.printf("%c Panels (P)\n", '-' if core.debug.panels else '+')
	if key_pressed(.P) do core.debug.panels = !core.debug.panels
	if core.debug.panels {
		sdtx.color3b(170, 170, 170)
		for id, &panel in core.panel_map {
			sdtx.printf(" {}\n", panel.box)
		}
		sdtx.color3b(255, 255, 255)
	}
}
