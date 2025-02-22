package demo

import onyx ".."
import vgo "../../vgo"
import "base:runtime"
import "core:c/libc"
import "core:fmt"
import img "core:image"
import "core:image/png"
import "core:math"
import "core:math/bits"
import "core:math/linalg"
import "core:math/rand"
import "core:mem"
import "core:os"
import "core:reflect"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:sys/windows"
import "core:thread"
import "core:time"
import "vendor:glfw"
import "vendor:wgpu"

FILLER_TEXT :: `1. In the beginning was the Word, and the Word was with God, and the Word was God.  2. The same was in the beginning with God.  3. All things were made by him; and without him was not any thing made that was made.  4. In him was life; and the life was the light of men.  5. And the light shineth in darkness; and the darkness comprehended it not.`

Section :: enum {
	Button,
	Boolean,
	Menu,
	Analog,
	Input,
	Chart,
	Grid,
	Navigation,
	Theme,
	Icon,
}

State :: struct {
	button_section:  Button_Section_State,
	boolean_section: Boolean_Section_State,
	graph_section:   Graph_Section_State,
	input_section:   Input_Section_State,
	analog_section:  Analog_Section_State,
	theme_section:   Theme_Section_State,
	nav_section:     Nav_Section_State,
	icon_section:    Icon_Section_State,
	current_section: Section,
}

destroy_state :: proc(state: ^State) {
	destroy_icon_section_state(&state.icon_section)
	state^ = {}
}

Boolean_Section_State :: struct {
	types: [onyx.Boolean_Type]bool,
}

boolean_section :: proc(state: ^Boolean_Section_State) {
	using onyx
	shrink(10)
	set_size_method(.Dont_Care)
	for type, i in Boolean_Type {
		push_id(i)
		boolean(&state.types[type], fmt.tprint(type), type = type)
		pop_id()
		space(10)
	}
}

Analog_Section_State :: struct {
	float_value:   f32,
	integer_value: int,
}

analog_section :: proc(state: ^Analog_Section_State) {
	using onyx
	shrink(10)
	set_size(0)
	slider(&state.float_value, 0, 100)
	space(10)
	slider(&state.integer_value, 0, 10)
	space(20)
	progress_bar(state.float_value / 100.0)
	space(20)
	dial(state.float_value / 100.0)
	space(20)
	pie({33, 15, 52}, 100, {vgo.RED, vgo.GREEN, vgo.BLUE})
}

Button_Section_State :: struct {}

button_section :: proc(state: ^Button_Section_State) {
	using onyx
	shrink(10)
	set_width(remaining_space().x)
	set_height(24)
	if begin_layout(side = .Left) {
		set_width(0)
		for accent, i in Button_Accent {
			push_id(i)
			button(fmt.tprint(accent), accent = accent)
			pop_id()
			space(10)
		}
		end_layout()
	}
	space(10)
	set_size(0)
	button("Button with\nmultiple lines\nof text", text_align = 0.5)
}

Input_Section_State :: struct {
	text:           string,
	multiline_text: string,
	number:         f32,
	date:           Maybe(onyx.Date),
	until:          Maybe(onyx.Date),
}

input_section :: proc(state: ^Input_Section_State) {
	using onyx
	shrink(10)
	set_width(200)
	set_height(30)
	input(state.text, placeholder = "placeholder")
	space(10)
	set_height(100)
	input(state.multiline_text, placeholder = "placeholder", flags = {.Multiline})
	space(10)
	set_height(30)
	input(state.number, prefix = "$")
}

Graph_Section_State :: struct {
	displayed_data: [40]f32,
	time_range:     [2]f32,
	value_range:    [2]f32,
	data:           [40]f32,
	color:          vgo.Color,
	show_points:    bool,
	show_crosshair: bool,
	snap_crosshair: bool,
	style:          onyx.Line_Chart_Fill_Style,
}

graph_section :: proc(state: ^Graph_Section_State) {
	using onyx
	shrink(10)
	set_side(.Bottom)
	set_height(26)
	if begin_layout(.Left) {
		set_align(.Center)
		set_width(0)
		if button("Randomize").clicked {
			randomize_graphs(state)
		}
		space(10)
		color_picker(&state.color)
		space(10)
		boolean(&state.show_points, "Points")
		space(10)
		boolean(&state.show_crosshair, "Crosshair")
		space(10)
		boolean(&state.snap_crosshair, "Snap Crosshair")
		space(10)
		option_slider(reflect.enum_field_names(Line_Chart_Fill_Style), &state.style)
		end_layout()
	}
	space(10)
	if begin_layout(.Left) {
		set_align(.Center)
		set_width(0)
		range_slider(&state.time_range.x, &state.time_range.y, 0, f64(len(state.data)))
		space(10)
		range_slider(&state.value_range.x, &state.value_range.y, -20, 20)
		end_layout()
	}
	space(10)
	set_size(remaining_space())

	if begin_graph(
		time_range = state.time_range,
		value_range = state.value_range,
		show_crosshair = state.show_crosshair,
		snap_crosshair = state.snap_crosshair,
		show_tooltip = true,
	) {
		curve_line_chart(
			state.displayed_data[:],
			state.color,
			show_points = state.show_points,
			fill_style = state.style,
		)

		end_graph()
	}

	for i in 0 ..< len(state.data) {
		difference := (state.data[i] - state.displayed_data[i])
		state.displayed_data[i] += difference * 10 * vgo.frame_time()
		draw_frames(int(abs(difference) > 0.01) * 2)
	}
}

randomize_graphs :: proc(state: ^Graph_Section_State) {
	range := [2]f32{0, 10}
	for i in 0 ..< len(state.data) {
		state.data[i] = rand.float32_range(range[0], range[1])
	}
}

Tab :: enum {
	First,
	Second,
	Third,
}

Nav_Section_State :: struct {
	tab: Tab,
}

nav_section :: proc(state: ^Nav_Section_State) {
	using onyx
	shrink(10)
	set_width(remaining_space().x)
	set_height(50)
	if begin_layout(.Left) {
		vgo.fill_box(current_box(), paint = style().color.field)
		set_width(0)
		set_height(30)
		set_align(.Far)
		for member, i in Tab {
			push_id(i)
			if tab(fmt.tprint(member), state.tab == member) {
				state.tab = member
			}
			pop_id()
		}
		end_layout()
	}
}

Theme_Option :: enum {
	Light,
	Dark,
	Custom,
}

Theme_Section_State :: struct {
	option: Theme_Option,
}

theme_section :: proc(state: ^Theme_Section_State) {
	using onyx
	struct_info := runtime.type_info_base(type_info_of(onyx.Color_Scheme)).variant.(runtime.Type_Info_Struct)
	shrink(10)
	set_width(remaining_space().x)
	set_height(26)
	set_side(.Bottom)
	if begin_layout(.Right) {
		set_width(0)
		if option_slider(reflect.enum_field_names(Theme_Option), &state.option).changed {
			if state.option == .Light {
				style().color = light_color_scheme()
			} else if state.option == .Dark {
				style().color = dark_color_scheme()
			}
		}
		space(10)
		slider(&style().rounding, 0, 10)
		space(10)
		slider(&style().default_text_size, 10, 30)
		end_layout()
	}

	begin_group()
	set_side(.Top)
	for i in 0 ..< struct_info.field_count {
		push_id(int(i))
		if begin_layout(.Left) {
			color := (^vgo.Color)(uintptr(&style().color) + struct_info.offsets[i])
			set_align(.Center)
			set_width_method(.Exact)
			set_width(150)
			label(struct_info.names[i])
			space(10)
			set_width(remaining_space().y)
			set_rounded_corners({.Top_Left, .Bottom_Right})
			color_picker(color, true)
			set_rounded_corners(ALL_CORNERS)
			space(10)
			set_width((remaining_space().x - 30) / 4)
			slider(&color.r, 0, 255)
			space(10)
			slider(&color.g, 0, 255)
			space(10)
			slider(&color.b, 0, 255)
			space(10)
			slider(&color.a, 0, 255)
			end_layout()
		}
		space(10)
		pop_id()
	}
	if group, ok := end_group(); ok {
		if .Changed in group.current_state {
			state.option = .Custom
		}
	}
}

recursive_menu :: proc(depth: int = 1, loc := #caller_location) {
	using onyx
	push_id(hash(loc))
	push_id("salty")
	push_id(depth)
	if begin_submenu("Open menu", 120, 3, 0) {
		menu_button("Option")
		menu_button("Option")
		recursive_menu(depth + 1)
		end_menu()
	}
	pop_id()
	pop_id()
	pop_id()
}

menu_section :: proc() {
	using onyx
	set_size(0)
	if begin_menu("Open menu", 120, 5, 1) {
		menu_button("Option")
		menu_button("Option")
		if begin_submenu("Open menu", 120, 3, 0) {
			menu_button("Option")
			menu_button("Option")
			end_menu()
		}
		if begin_submenu("Open menu", 120, 3, 0) {
			menu_button("Option")
			menu_button("Option")
			end_menu()
		}
		menu_divider()
		menu_button("Close")
		end_menu()
	}
	tooltip_text_layout := vgo.make_text_layout(
		"Click to open!",
		style().default_text_size,
		style().default_font,
	)
	if begin_tooltip_for_object(last_object().?, tooltip_text_layout.size + style().text_padding * 2) {
		vgo.fill_text_layout(
			tooltip_text_layout,
			box_center(current_object().?.box),
			0.5,
			style().color.content,
		)
		end_tooltip()
	}
}

example_browser :: proc(state: ^State) {
	using onyx
	set_next_box(view_box())

	if begin_layer(.Back) {

		if begin_layout(side = .Left) {

			shrink(40)

			set_rounded_corners(ALL_CORNERS)

			set_height(remaining_space().y)
			set_width(120)
			if begin_layout(.Top) {
				set_height(26)

				input(state.current_section)

				for section, i in Section {
					push_id(i)
					text, _ := strings.replace_all(
						fmt.tprint(section),
						"_",
						" ",
						allocator = context.temp_allocator,
					)
					if button(text, active = state.current_section == section, accent = .Subtle).pressed {
						state.current_section = section
					}
					space(4)
					pop_id()
				}

				end_layout()
			}

			space(20)

			set_width(remaining_space().x)
			if begin_layout(.Top) {
				foreground()

				#partial switch state.current_section {
				case .Button:
					button_section(&state.button_section)
				case .Boolean:
					boolean_section(&state.boolean_section)
				case .Menu:
					menu_section()
				case .Analog:
					analog_section(&state.analog_section)
				case .Input:
					input_section(&state.input_section)
				case .Chart:
					graph_section(&state.graph_section)
				case .Navigation:
					nav_section(&state.nav_section)
				case .Theme:
					theme_section(&state.theme_section)
				case .Icon:
					icon_section(&state.icon_section)
				}

				end_layout()
			}

			end_layout()
		}

		end_layer()
	}
}

main :: proc() {

	when ODIN_DEBUG {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)

		defer {
			if len(track.allocation_map) > 0 {
				fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
				for _, entry in track.allocation_map {
					fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
				}
			}
			if len(track.bad_free_array) > 0 {
				fmt.eprintf("=== %v incorrect frees: ===\n", len(track.bad_free_array))
				for entry in track.bad_free_array {
					fmt.eprintf("- %p @ %v\n", entry.memory, entry.location)
				}
			}
			mem.tracking_allocator_destroy(&track)
		}
	}

	glfw.Init()
	defer glfw.Terminate()

	window := glfw.CreateWindow(1400, 800, "demo", nil, nil)
	defer glfw.DestroyWindow(window)

	onyx.start(window)
	defer onyx.shutdown()

	state: State
	defer destroy_state(&state)

	panels: [5]onyx.Layer_Sort_Method

	rand.reset(rand.uint64())
	state.graph_section.color = vgo.GREEN
	state.graph_section.time_range = {0, 20}
	randomize_graphs(&state.graph_section)

	for {
		if glfw.WindowShouldClose(window) {
			break
		}
		{
			using onyx

			free_all(context.temp_allocator)

			new_frame()

			{
				box := view_box()
				vgo.fill_box(box, paint = style().color.background)
			}

			example_browser(&state)

			// for i in 0..<len(panels) {
			// 	push_id(i)
			// 	if begin_panel(sort_method = panels[i], size = [2]f32{220, 160}) {
			// 		layer := current_layer().?
			// 		shrink(10)
			// 		set_width(remaining_space().x)
			// 		set_height(26)
			// 		option_slider(reflect.enum_field_names(onyx.Layer_Sort_Method), &panels[i])
			// 		set_size(remaining_space())
			// 		label(fmt.tprintf("%v\n%i\n%i", layer.sort_method, layer.index, layer.floating_index))
			// 		// label(fmt.tprint(i), align = 0.5, font_size = 20)
			// 		end_panel()
			// 	}
			// 	pop_id()
			// }

			vgo.fill_text(fmt.tprint(global_state.layer_counts), 14, {0, global_state.view.y}, font = style().monospace_font, align = {0, 1}, paint = vgo.WHITE)

			present()
		}
	}
}
