package demo

import "core:fmt"
import "core:math"
import "core:strings"
import "base:runtime"
import "core:reflect"

import ui "extra:onyx/onyx"
import sapp "extra:sokol-odin/sokol/app"
import sg "extra:sokol-odin/sokol/gfx"

Option :: enum {
	Process,
	Wave,
	Manifold,
	Function,
}

Component_Section :: struct {
	component: enum {
		Button,
		Checkbox,
		Bar_Graph,
		Line_Graph,
	},
}

State :: struct {
	light_mode: bool,
	section: union {
		Component_Section,
	},

	checkboxes: [Option]bool,

	text_builder: strings.Builder,

	slider_value: f32,

	images: [4]ui.Image,
}

main :: proc() {
	state: State

	sapp.run(sapp.Desc{
		user_data = &state,
		init_userdata_cb = proc "c" (userdata: rawptr) {
			context = runtime.default_context()
			state := transmute(^State)userdata

			ui.init()
			ui.set_style_font(.Medium, "fonts/Geist-Medium.ttf")
			ui.set_style_font(.Bold, "fonts/Geist-Bold.ttf")
			ui.set_color_scheme(ui.dark_color_scheme())
			ui.set_style_rounding(0)

			for i in 0..<4 {
				state.images[i] = ui.load_image_from_file(fmt.aprintf("%i.png", i + 1)) or_else panic("failed lol")
			}
		},
		frame_userdata_cb = proc "c" (userdata: rawptr) {
			context = runtime.default_context()
			state := transmute(^State)userdata

			ui.begin_frame()
				ui.begin_layer({
					box = ui.shrink_box(ui.view_box(), 100),
				})
					ui.foreground()
					ui.begin_layout({
						size = 65,
						side = .Top,
						show_lines = true,
					})
						ui.shrink(15)
						ui.do_breadcrumb({text = "Components"})
						ui.do_breadcrumb({text = "Buttons", options = {"Fields", "Charts"}})
						ui.side(.Right)
						state.light_mode = ui.do_switch({on = state.light_mode}).on
					ui.end_layout()

					ui.shrink(30)
					switch section in state.section {
					
						case Component_Section:
						#partial switch section.component {
						
							case .Button:
							ui.do_label({
								text = "Fit to label",
								font_style = .Bold,
								font_size = 24,
							})
							ui.space(10)
							ui.begin_layout({
								size = 30,
							})
								ui.set_width_auto()
								for member, m in ui.Button_Kind {
									ui.push_id(m)
										if m > 0 {
											ui.space(10)
										}
										if ui.was_clicked(ui.do_button({
											text = ui.tmp_print(member),
											kind = member,
										})) {

										}
									ui.pop_id()
								}
							ui.end_layout()
							
						}
					}

				ui.end_layer()
				for i in 0..<4 {
					origin: [2]f32 = {
						0 + f32(i) * 200,
						sapp.heightf() - 200,
					}
					ui.draw_image(state.images[i], {origin, origin + 200}, {255, 255, 255, 255})
				}
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

		enable_clipboard = true,
		enable_dragndrop = true,
		sample_count = 4,
		width = 1000,
		height = 800,
		window_title = "o n y x",
	})
}
