package demo

import "base:runtime"
import "core:fmt"
import "core:math"
import "core:math/rand"
import "core:reflect"
import "core:strings"
import "core:time"

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
	light_mode:   bool,
	section:      Component_Section,
	checkboxes:   [Option]bool,
	text_builder: strings.Builder,
	slider_value: f32,
	start_time:   time.Time,
}

State :: struct {
	component_showcase: Component_Showcase,
	images:             [4]onyx.Image,
}

do_component_showcase :: proc(state: ^Component_Showcase) {
	using onyx

	layer_box := shrink_box(view_box(), 100)
	begin_layer({box = layer_box, kind = .Background})
	foreground()
	begin_layout({size = 65, side = .Top, show_lines = true})
	shrink(15)
	if index, ok := do_breadcrumb({index = int(state.section.component), options = reflect.enum_field_names(Component)}).index.?;
	   ok {
		state.section.component = Component(index)
	}
	side(.Right)
	state.light_mode = do_switch({on = state.light_mode}).on
	end_layout()
	shrink(30)

	#partial switch state.section.component {

	case .Button:
		side(.Top)
		do_label({text = "Fit to label", font_style = .Bold, font_size = 24})
		space(10)
		if do_layout({size = 30}) {
			set_width_auto()
			for member, m in Button_Kind {
				push_id(m)
				if m > 0 {
					space(10)
				}
				if was_clicked(do_button({text = tmp_print(member), kind = member})) {

				}
				pop_id()
			}
		}

	case .Checkbox:
		side(.Top)
		do_label({text = "checkboxes yo", font_style = .Bold, font_size = 24})
		space(10)
		for member, m in Option {
			push_id(m)
			if m > 0 {
				space(10)
			}
			if was_clicked(
				do_checkbox({text = tmp_print(member), value = state.checkboxes[member]}),
			) {
				state.checkboxes[member] = !state.checkboxes[member]
			}
			pop_id()
		}

	case .Data_Input:
		side(.Top)
		set_width(200)
		set_height(120)
		do_text_input(
			{builder = &state.text_builder, placeholder = "Type something", multiline = true},
		)
		space(10)
		do_text_input({builder = &state.text_builder})

	case .Bar_Graph:
		set_width_fill()
		set_height_fill()
		do_graph(
			Graph_Info(int) {
				lo = 0,
				hi = 10,
				increment = 1,
				spacing = 10,
				kind = Bar_Graph{show_labels = true, show_tooltip = true},
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
			},
		)

	case .Line_Graph:
		set_width_fill()
		set_height_fill()
		do_graph(
			Graph_Info(int) {
				lo = 0,
				hi = 20,
				increment = 10,
				spacing = 10,
				kind = Line_Graph{show_dots = false},
				fields = {{"Minecraft", {255, 25, 96, 255}}, {"Terraria", {0, 58, 255, 255}}},
				entries = {
					{values = {1, 5, 9}},
					{values = {4, 2, 2}},
					{values = {6, 5, 10}},
					{values = {2, 6, 1}},
					{values = {4, 7, 2}},
					{values = {2, 4, 8}},
					{values = {8, 5, 8}},
					{values = {18, 6, 8}},
					{values = {15, 7, 8}},
					{values = {14, 8, 8}},
					{values = {11, 6, 8}},
				},
			},
		)
	}
	end_layer()
}

main :: proc() {
	state: State

	sapp.run(
		sapp.Desc {
			user_data = &state,
			init_userdata_cb = proc "c" (userdata: rawptr) {
				context = runtime.default_context()
				state := transmute(^State)userdata

				onyx.init()
				onyx.set_style_font(.Medium, "fonts/Geist-Medium.ttf")
				onyx.set_style_font(.Bold, "fonts/Geist-Bold.ttf")
				onyx.set_style_font(.Light, "fonts/Geist-Light.ttf")
				onyx.set_style_font(.Regular, "fonts/Geist-Regular.ttf")

				// for i in 0 ..< 4 {
				// 	state.images[i] =
				// 		onyx.load_image_from_file(fmt.aprintf("%i.png", i + 1)) or_else panic(
				// 			"failed lol",
				// 		)
				// }
			},
			frame_userdata_cb = proc "c" (userdata: rawptr) {
				context = runtime.default_context()
				state := transmute(^State)userdata

				using onyx
				begin_frame()
				do_component_showcase(&state.component_showcase)

				// if do_panel({title = "Widgets"}) {
				// 	shrink(30)
				// 	side(.Top)
				// 	colors := [6]Color {
				// 		{255, 60, 60, 255},
				// 		{0, 255, 120, 255},
				// 		{255, 10, 220, 255},
				// 		{240, 195, 0, 255},
				// 		{30, 120, 255, 255},
				// 		{0, 255, 0, 255},
				// 	}
				// 	for color, c in colors {
				// 		if c > 0 do space(10)
				// 		if do_layout({size = 30, side = .Top}) {
				// 			for kind, k in Button_Kind {
				// 				if k > 0 do space(10)
				// 				button_text := tmp_printf("Button %c%i", 'A' + c, k + 1)
				// 				push_id(button_text)
				// 				do_button({text = button_text, color = color, kind = kind})
				// 				pop_id()
				// 			}
				// 		}
				// 	}
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
			width = 1800,
			height = 960,
			// fullscreen = true,
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
		},
	)
}
