package demo

import ui ".."

import "core:fmt"
import "core:math"
import "core:runtime"

import sapp "extra:sokol-odin/sokol/app"

mobile_data: []int = {10, 5, 0, 14, 29, 49, 36, 35, 38, 1, 7, 12, 4}
desktop_data: []int = {2, 4, 2, 15, 25, 2, 23, 15, 15, 12, 15, 0, 5, 2, 2, 1, 9, 5, 8, 10}
checkbox_value: bool

main :: proc() {
	sapp.run(sapp.Desc{
		init_cb = proc "c" () {
			context = runtime.default_context()

			ui.init()
			ui.set_style_font(.Medium, "fonts/Geist-Medium.ttf")
			ui.set_style_font(.Bold, "fonts/Geist-Bold.ttf")
			ui.set_color_scheme(ui.dark_color_scheme())
			ui.set_style_rounding(2)
		},
		frame_cb = proc "c" () {
			context = runtime.default_context()

			ui.begin_frame()
				ui.begin_layer({
					box = ui.view_box(),
				})
					ui.padding(100)
					ui.begin_layout_cut(.Top, 65, .Left)
						ui.foreground()
						ui.padding(15)
						ui.button({text = "your", kind = .Primary})
						ui.space(10)
						ui.button({text = "house", kind = .Secondary})
						ui.space(10)
						ui.button({text = "is", kind = .Outlined})
						ui.space(10)
						ui.button({text = "flammable", kind = .Ghost})
					ui.end_layout()
					ui.space(20)
					ui.begin_layout_cut(.Top, 65, .Left)
						ui.foreground()
						ui.padding(15)
						ui.size(200)
						if ui.was_clicked(ui.checkbox({text = "checkbox", value = checkbox_value})) {
							checkbox_value = !checkbox_value
						}
					ui.end_layout()
					ui.space(20)
					ui.size(300)
					ui.graph(ui.Graph_Info(int){
						kind = ui.Graph_Kind_Bar{
							show_labels = true,
							stacked = true,
						},
						low = 0,
						high = 50,
						increment = 10,
						fields = {
							{name = "mobile", color = {80, 255, 100, 255}},
							{name = "desktop", color = {120, 60, 255, 255}},
						},
						entries = {
							{label = "Jan", values = {15, 25}},
							{label = "Feb", values = {12, 6}},
							{label = "Mar", values = {4, 25}},
							{label = "Apr", values = {5, 12}},
							{label = "May", values = {2, 13}},
							{label = "Jun", values = {1, 16}},
							{label = "Jul", values = {8, 10}},
							{label = "Aug", values = {26, 5}},
							{label = "Sep", values = {43, 6}},
							{label = "Oct", values = {41, 26}},
							{label = "Nov", values = {34, 22}},
							{label = "Dec", values = {25, 17}},
						},
					})
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