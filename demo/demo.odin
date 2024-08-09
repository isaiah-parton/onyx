package demo

import "core:fmt"
import "core:math"
import "core:time"
import "core:strings"
import "base:runtime"
import "core:reflect"

import "extra:onyx/onyx"
import sapp "extra:sokol-odin/sokol/app"
import sg "extra:sokol-odin/sokol/gfx"

Option :: enum {
	Process,
	Wave,
	Manifold,
	Function,
}

Component :: enum {
	Button,
	Checkbox,
	Bar_Graph,
	Line_Graph,
}

Component_Section :: struct {
	component: Component,
}

State :: struct {
	light_mode: bool,
	section: Component_Section,
	checkboxes: [Option]bool,

	text_builder: strings.Builder,

	slider_value: f32,

	images: [4]onyx.Image,

	start_time: time.Time,
}

main :: proc() {
	state: State

	sapp.run(sapp.Desc{
		user_data = &state,
		init_userdata_cb = proc "c" (userdata: rawptr) {
			context = runtime.default_context()
			state := transmute(^State)userdata

			onyx.init()
			onyx.set_style_font(.Medium, "fonts/Geist-Medium.ttf")
			onyx.set_style_font(.Bold, "fonts/Geist-Bold.ttf")
			onyx.set_color_scheme(onyx.dark_color_scheme())
			onyx.set_style_rounding(7)

			// for i in 0..<4 {
			// 	state.images[i] = onyx.load_image_from_file(fmt.aprintf("%i.png", i + 1)) or_else panic("failed lol")
			// }

			state.start_time = time.now()
		},
		frame_userdata_cb = proc "c" (userdata: rawptr) {
			context = runtime.default_context()
			state := transmute(^State)userdata

			using onyx
			begin_frame()
				layer_box := shrink_box(view_box(), 100)
				begin_layer({
					box = layer_box,
				})
					foreground()
					begin_layout({
						size = 65,
						side = .Top,
						show_lines = true,
					})
						shrink(15)
						do_breadcrumb({index = 0, options = {"Components"}})
						if index, ok := do_breadcrumb({index = int(state.section.component), options = reflect.enum_field_names(Component)}).index.?; ok {
							state.section.component = Component(index)
						}
						side(.Right)
						state.light_mode = do_switch({on = state.light_mode}).on
					end_layout()
					shrink(30)
					
					#partial switch state.section.component {
					
						case .Button:
						side(.Top)
						do_label({
							text = "Fit to label",
							font_style = .Bold,
							font_size = 24,
						})
						space(10)
						begin_layout({
							size = 30,
						})
							set_width_auto()
							for member, m in Button_Kind {
								push_id(m)
									if m > 0 {
										space(10)
									}
									if was_clicked(do_button({
										text = tmp_print(member),
										kind = member,
									})) {

									}
								pop_id()
							}
						end_layout()
					}
					begin_layer({
						box = {250, 500},
						order = .Floating,
					})
						foreground()
					end_layer()

					begin_layer({
						box = {{300, 150}, {600, 450}},
						order = .Floating,
					})
						foreground()
					end_layer()
				end_layer()


				// for i in 0..<4 {
				// 	origin: [2]f32 = {
				// 		0 + f32(i) * 200,
				// 		sapp.heightf() - 200,
				// 	}
				// 	onyx.draw_image(state.images[i], {origin, origin + 200}, {255, 255, 255, 255})
				// }
			onyx.end_frame()
		},
		cleanup_cb = proc "c" () {
			context = runtime.default_context()

			onyx.quit()
		},
		event_cb = proc "c" (e: ^sapp.Event) {
			context = runtime.default_context()

			onyx.handle_event(e)
		},

		enable_clipboard = true,
		enable_dragndrop = true,
		sample_count = 4,
		width = 1000,
		height = 800,
		window_title = "o n y x",
		// icon = sapp.Icon_Desc{
		// 	images = {
		// 		0 = {
		// 			width = 2,
		// 			height = 2,
		// 			pixels = {
						
		// 			},
		// 		},
		// 	},
		// },
	})
}
