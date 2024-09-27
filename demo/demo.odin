package demo

import "base:runtime"
import "core:fmt"
import "core:math"
import "core:math/rand"
import "core:mem"
import "core:reflect"
import "core:strings"
import "core:time"
import "core:os"

import onyx "../onyx"
import "vendor:glfw"

Option :: enum {
	Process,
	Wave,
	Manifold,
	Function,
}

Component :: enum {
	Tables,
	Button,
	Data_Input,
	Boolean,
	Graph,
	Slider,
	Scroll_Zone,
}

Component_Section :: struct {
	component: Component,
}

Component_Showcase :: struct {
	light_mode:    bool,
	section:       Component_Section,
	checkboxes:    [Option]bool,
	bio:           strings.Builder,
	full_name:     strings.Builder,
	birth_country: strings.Builder,
	slider_value:  f64,
	start_time:    time.Time,
	option:        Option,
	date_range:    [2]Maybe(onyx.Date),
	month_offset:  int,
	entries:       [dynamic]Table_Entry,
}

State :: struct {
	component_showcase: Component_Showcase,
	images:             [4]onyx.Image,
}

Table_Entry :: struct {
	name:        string,
	hash:        string,
	public_key:  string,
	private_key: string,
	location:    string,
}

do_component_showcase :: proc(state: ^Component_Showcase) {
	using onyx

	if do_panel({title = "Login"}) {
		shrink(10)
		button({text = "Login"})
		button({text = "Login"})
	}

	layer_box := shrink_box(view_box(), 100)
	begin_layer({box = layer_box, kind = .Background})
	foreground()
	if layout({size = 65, side = .Top}) {
		shrink(15)
		tabs({index = (^int)(&state.section.component), options = reflect.enum_field_names(Component)})
		set_side(.Right)
		toggle_switch({state = &state.light_mode})
	}
	shrink(40)

	#partial switch state.section.component {
	case .Tables:
		set_side(.Top)
		rows_active: [dynamic]bool
		resize(&rows_active, len(state.entries))
		if table(
			{
				columns = {
					{name = "Name"},
					{name = "Hash", width = 200, sorted = .Ascending},
					{name = "Public Key"},
					{name = "Private Key"},
					{name = "Location"},
				},
				row_count = len(state.entries),
				max_displayed_rows = 15,
			},
		) {
			table := &current_widget().?.table
			for index in table.first ..= table.last {
				entry := &state.entries[index]
				begin_table_row({index = index})
				set_width_auto()
				text_input({content = &entry.name, undecorated = true})
				text_input({content = &entry.hash, undecorated = true})
				text_input({content = &entry.public_key, undecorated = true})
				text_input({content = &entry.private_key, undecorated = true})
				text_input({content = &entry.location, undecorated = true})
				end_table_row()
			}
		}

	case .Scroll_Zone:
		set_side(.Left)
		set_width(300)
		set_height_fill()
		if _, ok := do_container({size = {0, 2000}}); ok {
			set_width_fill()
			set_height_auto()
			for i in 0 ..< 50 {
				if i > 0 {
					add_space(4)
				}
				push_id(i)
				button(
					{text = fmt.tprintf("Button #%i", i + 1), style = .Ghost},
				)
				pop_id()
			}
		}
		add_space(50)
		set_width(500)
		set_height(300)
		if _, ok := do_container({size = {1000, 0}}); ok {
			set_side(.Left)
			set_height_fill()
			set_width(200)
			set_padding(10)
			for i in 0 ..< 5 {
				push_id(i)
				button({text = fmt.tprint(i + 1), style = .Outlined})
				pop_id()
			}
		}

	case .Slider:
		set_side(.Top)
		do_label({text = "Normal"})
			slider({value = &state.slider_value})
		add_space(10)
		do_label({text = "Box"})
		add_space(10)
			box_slider({value = &state.slider_value})

	case .Button:
		set_side(.Top)
		do_label({text = "Fit to label"})
		add_space(10)
		if layout({size = 30}) {
			set_width_auto()
			for member, m in Button_Kind {
				push_id(m)
				if m > 0 {
					add_space(10)
				}
				if was_clicked(
					button({text = fmt.tprint(member), style = member}),
				) {

				}
				pop_id()
			}
		}
		add_space(10)
		if do_selector({text = "Combo"}) {
			shrink(3)
			set_side(.Top)
			set_width_fill()
			for option, o in Option {
				push_id(o)
				if was_clicked(
					do_selector_option(
						{
							text = fmt.tprint(option),
							state = state.option == option,
						},
					),
				) {
					state.option = option
				}
				pop_id()
			}
		}

	case .Boolean:
		set_side(.Top)
		do_label({text = "Checkboxes"})
		add_space(10)
		for member, m in Option {
			push_id(m)
			if m > 0 {
				add_space(10)
			}
			if was_clicked(
				do_checkbox(
					{
						text = fmt.tprint(member),
						state = state.checkboxes[member],
					},
				),
			) {
				state.checkboxes[member] = !state.checkboxes[member]
			}
			pop_id()
		}
		add_space(10)
		do_label({text = "Radio Buttons"})
		add_space(10)
		for member, m in Option {
			push_id(m)
			if m > 0 {
				add_space(10)
			}
			if was_clicked(
				do_radio_button(
					{text = fmt.tprint(member), state = state.option == member},
				),
			) {
				state.option = member
			}
			pop_id()
		}

	case .Data_Input:
		set_side(.Top)
		set_width(250)
		add_space(10)
		set_height_auto()
		text_input(
			{
				content = &state.full_name,
				placeholder = "Full Name",
				decal = .Check,
			},
		)
		add_space(10)
		text_input(
			{content = &state.birth_country, placeholder = "Country of birth"},
		)
		add_space(10)
		set_height_auto()
		date_picker({first = &state.date_range[0]})
		add_space(10)
		date_picker({first = &state.date_range[0], second = &state.date_range[1]})
		add_space(10)
		set_height(120)
		text_input(
			{content = &state.bio, placeholder = "Bio", multiline = true},
		)

	case .Graph:
		set_side(.Left)
		set_width_percent(50)
		if layout({}) {
			shrink(30)
			set_width_fill()
			set_height_fill()
			do_graph(
				Graph_Info(int) {
					lo = 0,
					hi = 30,
					increment = 5,
					spacing = 10,
					style = Bar_Graph{value_labels = true, show_tooltip = true},
					label_tooltip = true,
					fields = {
						{"Field 1", {255, 25, 96, 255}},
						{"Field 2", {0, 58, 255, 255}},
					},
					entries = {
						{"Feb 2nd", {1, 5}},
						{"Feb 3rd", {4, 2}},
						{"Feb 4th", {6, 5}},
						{"Feb 5th", {2, 8}},
						{"Feb 6th", {3, 12}},
						{"Feb 7th", {4, 13}},
						{"Feb 8th", {4, 10}},
						{"Feb 9th", {5, 10}},
						{"Feb 10th", {7, 7}},
						{"Feb 11th", {8, 6}},
						{"Feb 12th", {11, 6}},
						{"Feb 13th", {12, 7}},
						{"Feb 14th", {9, 4}},
					},
				},
			)
		}
		if layout({}) {
			shrink(30)
			set_width_fill()
			set_height_fill()
			do_graph(
				Graph_Info(int) {
					lo = 0,
					hi = 30,
					increment = 5,
					spacing = 10,
					style = Line_Graph{show_dots = false},
					label_tooltip = true,
					fields = {
						{"Minecraft", {255, 25, 96, 255}},
						{"Terraria", {0, 58, 255, 255}},
					},
					entries = {
						{label = "Jan 5th", values = {1, 5}},
						{label = "Jan 6th", values = {4, 2}},
						{label = "Jan 7th", values = {6, 5}},
						{label = "Jan 8th", values = {2, 6}},
						{label = "Jan 9th", values = {4, 7}},
						{label = "Jan 10th", values = {2, 4}},
						{label = "Jan 11th", values = {8, 5}},
						{label = "Jan 12th", values = {18, 6}},
						{label = "Jan 13th", values = {15, 7}},
						{label = "Jan 14th", values = {14, 8}},
						{label = "Jan 15th", values = {11, 6}},
					},
				},
			)
		}
	}
	end_layer()
}

allocator: runtime.Allocator

main :: proc() {
	when ODIN_DEBUG {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		allocator = mem.tracking_allocator(&track)

		defer {
			if len(track.allocation_map) > 0 {
				fmt.eprintf(
					"=== %v allocations not freed: ===\n",
					len(track.allocation_map),
				)
				for _, entry in track.allocation_map {
					fmt.eprintf(
						"- %v bytes @ %v\n",
						entry.size,
						entry.location,
					)
				}
			}
			if len(track.bad_free_array) > 0 {
				fmt.eprintf(
					"=== %v incorrect frees: ===\n",
					len(track.bad_free_array),
				)
				for entry in track.bad_free_array {
					fmt.eprintf("- %p @ %v\n", entry.memory, entry.location)
				}
			}
			mem.tracking_allocator_destroy(&track)
		}
	} else {
		allocator = runtime.default_allocator()
	}

	state: State

	state.component_showcase.date_range = {
		onyx.Date{2024, 2, 17},
		onyx.Date{2024, 3, 2},
	}

	for i in 0 ..< 100 {
		append(
			&state.component_showcase.entries,
			Table_Entry {
				hash = fmt.aprintf("%x", rand.int31()),
				name = fmt.aprintf("%v", i + 1),
				public_key = fmt.aprintf("%x", rand.int31()),
				private_key = fmt.aprintf("%x", rand.int31()),
				location = fmt.aprintf("%x", rand.int31()),
			},
		)
	}

	onyx.init(1600, 900, "demo")
	onyx.set_style_font(.Medium, "fonts/Geist-Medium.ttf")
	onyx.set_style_font(.Bold, "fonts/Geist-Bold.ttf")
	onyx.set_style_font(.Light, "fonts/Geist-Light.ttf")
	onyx.set_style_font(.Regular, "fonts/Geist-Regular.ttf")
	onyx.set_style_font(.Icon, "fonts/remixicon.ttf")

	for !glfw.WindowShouldClose(onyx.core.window) {
		onyx.new_frame()
		do_component_showcase(&state.component_showcase)
		onyx.render()
	}

	onyx.uninit()
}
