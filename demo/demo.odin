package demo

import ui ".."

import "core:fmt"
import "core:math"

main :: proc() {

	ui.run({
		width = 1000,
		height = 800,
		title = "UI DEMO",
		init_cb = proc(_: rawptr) {
			ui.set_style_font("Gabarito-Regular.ttf")
			ui.set_color_scheme(ui.dark_color_scheme())
			ui.set_style_rounding(8)
		},
		frame_cb = proc(_: rawptr) {
			ui.begin_layer(ui.view_box())
				ui.padding(100)
				ui.begin_layout_cut(.Top, 40, .Left)
					ui.padding(4)
					ui.button({text = "gyatt"})
					ui.space(20)
					ui.button({text = "skibidy"})
				ui.end_layout()
			ui.end_layer()
		},
	})

}