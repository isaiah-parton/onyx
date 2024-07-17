package demo

import ui ".."

main :: proc() {

	ui.run({
		width = 1000,
		height = 800,
		title = "UI DEMO",
		frame_cb = proc(data: rawptr) {
			ui.begin_layer(ui.view_box())
				/*ui.begin_row(align_self = .Top, align_contents = .Center, height = 30)
					ui.button("gyatt")
					ui.space(20)
					ui.button("skibidy")
				ui.end_row()*/
			ui.end_layer()
		},
	})

}