package demo

import "core:fmt"
import "core:math"
import "core:math/rand"
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
	Data_Input,
	Checkbox,
	Bar_Graph,
	Line_Graph,
}

Component_Section :: struct {
	component: Component,
}

Component_Showcase :: struct {
	light_mode: bool,
	section: Component_Section,
	checkboxes: [Option]bool,

	text_builder: strings.Builder,

	slider_value: f32,

	images: [4]onyx.Image,

	start_time: time.Time,
}

State :: struct {
	component_showcase: Component_Showcase,
}

do_component_showcase :: proc(state: ^Component_Showcase) {
	using onyx

	layer_box := shrink_box(view_box(), 100)
	begin_layer({
		box = layer_box,
		kind = .Background,
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

			case .Checkbox:
			side(.Top)
			do_label({
				text = "checkboxes yo",
				font_style = .Bold,
				font_size = 24,
			})
			space(10)
			for member, m in Option {
				push_id(m)
					if m > 0 {
						space(10)
					}
					if was_clicked(do_checkbox({
						text = tmp_print(member),
						value = state.checkboxes[member],
					})) {
						state.checkboxes[member] = !state.checkboxes[member]
					}
				pop_id()
			}

			case .Data_Input:
			side(.Top)
			set_width(200)
			do_text_input({
				builder = &state.text_builder,
				placeholder = "Type something",
			})

			case .Bar_Graph:
			set_width_fill()
			set_height_fill()
			do_graph(Graph_Info(int){
				lo = 0,
				hi = 10,
				increment = 1,
				spacing = 10,
				kind = Bar_Graph{
					show_labels = true,
					show_tooltip = true,
				},
				fields = {
					{"Ohio", {255, 100, 100, 255}},
					{"Florida", {0, 100, 255, 255}},
					{"Alabama", {0, 255, 120, 255}},
				},
				entries = {
					{"Skibidy", {1, 5, 9}},
					{"Rizzler", {4, 2, 2}},
					{"Gooner", {6, 5, 10}},
					{"Sigma", {2, 8, 1}},
				},
			})

			case .Line_Graph:
			set_width_fill()
			set_height_fill()
			do_graph(Graph_Info(int){
				lo = 0,
				hi = 50,
				increment = 10,
				spacing = 10,
				kind = Line_Graph{
					show_dots = true,
				},
				fields = {
					{"Ohio", {255, 100, 100, 255}},
					{"Florida", {0, 100, 255, 255}},
					{"Alabama", {0, 255, 120, 255}},
				},
				entries = {
					{values = {1, 5, 9}},
					{values = {4, 2, 2}},
					{values = {6, 5, 10}},
					{values = {2, 8, 1}},
					{values = {4, 7, 2}},
					{values = {2, 4, 8}},
				},
			})
		}
	end_layer()
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
			onyx.set_style_font(.Light, "fonts/Geist-Light.ttf")
			onyx.set_style_font(.Regular, "fonts/Geist-Regular.ttf")
			onyx.set_color_scheme(onyx.dark_color_scheme())
			onyx.set_style_rounding(4)

			// for i in 0..<4 {
			// 	state.images[i] = onyx.load_image_from_file(fmt.aprintf("%i.png", i + 1)) or_else panic("failed lol")
			// }
		},
		frame_userdata_cb = proc "c" (userdata: rawptr) {
			context = runtime.default_context()
			state := transmute(^State)userdata

			using onyx
			begin_frame()
				do_component_showcase(&state.component_showcase)

				// for i in 0..<4 {
				// 	push_id(i)
				// 		begin_panel({
				// 			title = tmp_printf("Panel #{}", i + 1),
				// 		})

				// 		end_panel()
				// 	pop_id()
				// }

				// for i in 0..<4 {
				// 	origin: [2]f32 = {
				// 		0 + f32(i) * 200,
				// 		sapp.heightf() - 200,
				// 	}
				// 	onyx.draw_image(state.images[i], {origin, origin + 200}, {255, 255, 255, 255})
				// }
			end_frame()
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
