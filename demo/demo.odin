package demo

import ui ".."

import "core:fmt"
import "core:math"
import "core:runtime"

import sapp "../../sokol-odin/sokol/app"

main :: proc() {

	sapp.run(sapp.Desc{
		init_cb = proc "c" () {
			context = runtime.default_context()

			ui.init()
			ui.set_style_font("Geist-Bold.ttf")
			ui.set_style_thin_font("Geist-Medium.ttf")
			ui.set_color_scheme(ui.dark_color_scheme())
			ui.set_style_rounding(8)
		},
		frame_cb = proc "c" () {
			context = runtime.default_context()

			ui.begin_frame()
				ui.begin_layer(ui.view_box())
					ui.padding(100)
					ui.begin_layout_cut(.Top, 65, .Left)
						ui.foreground()
						ui.padding(15)
						ui.button({text = "skibidy"})
						ui.space(10)
						ui.button({text = "gyatt"})
						ui.space(10)
						ui.button({text = "rizzler", kind = .Ghost})
						ui.space(10)
						ui.button({text = "ohio", kind = .Secondary})
					ui.end_layout()
					ui.space(20)
					ui.begin_layout_cut(.Top, 65, .Left)
						ui.foreground()
						ui.padding(15)
						ui.button({text = "fanum tax"})
						ui.space(10)
						ui.side(.Right)
						ui.button({text = "buzzword", kind = .Outlined})
					ui.end_layout()
				ui.end_layer()
			ui.end_frame()
		},
		cleanup_cb = proc "c" () {
			context = runtime.default_context()

			ui.quit()
		},
		event_cb = proc "c" (e: ^sapp.Event) {
			context = runtime.default_context()

			ui.handle_event(e)
		},

		sample_count = 4,
		width = 1000,
		height = 800,
		window_title = "UI DEMO",
	})
}