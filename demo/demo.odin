package demo

import ui ".."

import "core:math"

main :: proc() {

	ui.run({
		width = 1000,
		height = 800,
		title = "UI DEMO",
		frame_cb = proc(data: rawptr) {
			ui.begin_layer(ui.view_box())
				ui.begin_row(align_self = .Top, align_contents = .Center, height = 30)
					ui.button({text = "gyatt"})
					ui.space(20)
					ui.button({text = "skibidy"})
				ui.end_row()
			ui.end_layer()
		},
	})

}