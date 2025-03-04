package demo

import "local:ronin"
import kn "local:katana"
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

FILLER_TEXT :: `Lorem ipsum odor amet, consectetuer adipiscing elit. Feugiat per venenatis at himenaeos odio ante ante pretium vestibulum. Natoque finibus est consequat orci et curae. Mollis odio massa dictumst mus metus eros aliquam quam. Commodo laoreet ultrices hac conubia ultricies suspendisse magna phasellus magna. Pulvinar tempor maximus venenatis ex pellentesque vitae purus. Ullamcorper aptent inceptos lectus molestie fermentum consectetur tempor. Platea porttitor auctor mattis nisi ut urna lectus magnis risus.`

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
	types: [ronin.Boolean_Type]bool,
}

boolean_section :: proc(state: ^Boolean_Section_State) {
	using ronin
	shrink(10)
	for type, i in Boolean_Type {
		push_id(i)
		boolean(&state.types[type], fmt.tprint(type), type = type)
		pop_id()
		space()
	}
}

Analog_Section_State :: struct {
	float_value:   f32,
	integer_value: int,
	float_range: [2]f32,
}

analog_section :: proc(state: ^Analog_Section_State) {
	using ronin
	shrink(10)
	set_size(that_of_object)
	slider(&state.float_value, 0, 100)
	space()
	slider(&state.integer_value, 0, 10)
	space()
	set_height(to_scale(1))
	if do_layout(as_row) {
		set_width(that_of_object)
		h1("Range sliders")
	}
	space()
	set_height(to_scale(1))
	set_width(to_layout_width)
	if do_layout(as_row) {
		set_width(that_of_object)
		range_slider(&state.float_range[0], &state.float_range[1], 0, 100)
	}
	set_height(that_of_object)
	space()
	progress_bar(state.float_value / 100.0)
	space()
	dial(state.float_value / 100.0)
	space()
	pie({33, 15, 52}, 100, {kn.Red, kn.Green, kn.Blue})
}

Button_Section_State :: struct {}

button_section :: proc(state: ^Button_Section_State) {
	using ronin
	shrink(10)
	set_width(to_layout_width)
	set_height(to_scale(1))
	if do_layout(as_row) {
		set_width(that_of_object)
		for accent, i in Button_Accent {
			push_id(i)
			button(fmt.tprint(accent), accent = accent)
			pop_id()
			space()
		}
	}
	space()
	set_size(that_of_object)
	button("Button with\nmultiple lines\nof text", text_align = 0.5)
}

Input_Section_State :: struct {
	text:           string,
	multiline_text: string,
	number:         f32,
	date:           Maybe(ronin.Date),
	until:          Maybe(ronin.Date),
}

input_section :: proc(state: ^Input_Section_State) {
	using ronin
	shrink(10)
	set_width(to_scale(3))
	set_height()
	input(state.text, with_placeholder("placeholder"))
	space()
	set_height(to_scale(3))
	input(state.multiline_text, with_placeholder("placeholder"), with_multiline)
	space()
	set_height(to_scale(1))
	input(state.number, with_prefix("$"))
}

Graph_Section_State :: struct {
	displayed_data: [40]f32,
	time_range:     [2]f32,
	value_range:    [2]f32,
	data:           [40]f32,
	color:          kn.Color,
	show_points:    bool,
	show_crosshair: bool,
	snap_crosshair: bool,
	style:          ronin.Line_Chart_Fill_Style,
}

graph_section :: proc(state: ^Graph_Section_State) {
	using ronin
	shrink(10)
	set_height()
	if do_layout(as_row) {
		set_align(0.5)
		set_width(to_scale(1))
		if button("Randomize").clicked {
			randomize_graphs(state)
		}
		space()
		color_picker(&state.color)
		space()
		boolean(&state.show_points, "Points")
		space()
		boolean(&state.show_crosshair, "Crosshair")
		space()
		boolean(&state.snap_crosshair, "Snap Crosshair")
		space()
		option_slider(reflect.enum_field_names(Line_Chart_Fill_Style), &state.style)
	}
	space()
	if do_layout(as_row) {
		set_align(0.5)
		set_width(that_of_object)
		range_slider(&state.time_range.x, &state.time_range.y, 0, f64(len(state.data)))
		space()
		range_slider(&state.value_range.x, &state.value_range.y, -20, 20)
	}
	space()
	set_size(to_layout_size)

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
		state.displayed_data[i] += difference * 10 * kn.frame_time()
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
	using ronin
	shrink(10)
	set_width(to_layout_width)
	set_height(to_scale(5))
	if do_layout(as_row) {
		kn.add_box(get_current_layout().box, paint = get_current_style().color.field)
		set_width(that_of_object)
		set_height(to_scale(1))
		set_align(1)
		for member, i in Tab {
			push_id(i)
			if tab(fmt.tprint(member), state.tab == member) {
				state.tab = member
			}
			pop_id()
		}
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
	using ronin
	struct_info := runtime.type_info_base(type_info_of(ronin.Color_Scheme)).variant.(runtime.Type_Info_Struct)
	shrink(10)
	set_width(to_layout_width)
	set_height(to_scale(1))
	if do_layout(as_reversed_row) {
		set_width(that_of_object)
		if option_slider(reflect.enum_field_names(Theme_Option), &state.option).changed {
			if state.option == .Light {
				get_current_style().color = light_color_scheme()
			} else if state.option == .Dark {
				get_current_style().color = dark_color_scheme()
			}
		}
		space()
		slider(&get_current_style().rounding, 0, 10)
		space()
		slider(&get_current_style().default_text_size, 10, 30)
	}

	begin_group()
	for i in 0 ..< struct_info.field_count {
		push_id(int(i))
		if do_layout(as_row) {
			color := (^kn.Color)(uintptr(&get_current_style().color) + struct_info.offsets[i])
			set_align(0.5)
			set_width(to_scale(5))
			label(struct_info.names[i])
			space()
			set_width(to_layout_height)
			set_rounded_corners({.Top_Left, .Bottom_Right})
			color_picker(color, true)
			set_rounded_corners(ALL_CORNERS)
			space()
			set_width(of_layout_width(1/4))
			slider(&color.r, 0, 255)
			space()
			slider(&color.g, 0, 255)
			space()
			slider(&color.b, 0, 255)
			space()
			slider(&color.a, 0, 255)
		}
		space()
		pop_id()
	}
	if group, ok := end_group(); ok {
		if .Changed in group.current_state {
			state.option = .Custom
		}
	}
}

recursive_menu :: proc(depth: int = 1, loc := #caller_location) {
	using ronin
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
	using ronin
	set_size(that_of_object)
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
	tooltip_text := kn.make_text(
		"Click to open!",
		get_current_style().default_text_size,
		get_current_style().default_font,
	)
	if begin_tooltip_for_object(last_object().?, tooltip_text.size + get_current_style().text_padding * 2) {
		kn.add_text(
			tooltip_text,
			box_center(get_current_layout().box) - tooltip_text.size * 0.5,
			get_current_style().color.content,
		)
		end_tooltip()
	}
}

example_browser :: proc(state: ^State) {
	using ronin
	set_next_box(view_box())

	if begin_layer(.Back) {

		if do_layout(as_row) {

			shrink(40)

			set_rounded_corners(ALL_CORNERS)

			set_height(to_layout_height)
			set_width(to_scale(1))
			if do_layout(as_column) {
				set_height(to_scale(1))
				input(state.current_section)
				for section, i in Section {
					push_id(i)
					text, _ := strings.replace_all(
						fmt.tprint(section),
						"_",
						" ",
						allocator = context.temp_allocator,
					)
					set_height(to_scale(4))
					if button(text, active = state.current_section == section, accent = .Subtle).pressed {
						state.current_section = section
					}
					set_height(exactly(4))
					space()
					pop_id()
				}
			}

			space()

			set_width(remaining_space().x)
			if do_layout(top_to_bottom) {
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
			}
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

	ronin.start(window)
	defer ronin.shutdown()

	state: State
	defer destroy_state(&state)

	panels: [5]ronin.Layer_Sort_Method

	rand.reset(rand.uint64())
	state.graph_section.color = kn.Green
	state.graph_section.time_range = {0, 20}
	randomize_graphs(&state.graph_section)

	for {
		if glfw.WindowShouldClose(window) {
			break
		}
		{
			using ronin

			free_all(context.temp_allocator)

			new_frame()

			{
				box := view_box()
				kn.add_box(box, paint = get_current_style().color.background)
			}

			if do_panel(with_size(300)) {
				shrink(get_current_style().scale)
				set_width(to_scale(10))
				button("i'm a panel")
				button("\ue4e7", accent = .Subtle)
			}

			// example_browser(&state)
			set_size(to_layout_size)
			if do_carousel() {
				if do_page(as_column) {
					if do_layout(as_column, center_contents, with_box(align_box_inside(get_current_layout().box, 200, 0.5))) {
						set_size(that_of_object)
						set_axis_locks(false, true)
						h1("Ronin")
						text("while (1) {fork()};", font = get_current_style().monospace_font)
						space()
						set_width(to_scale(8))
						if button("Continue\ue391").clicked {
							pages_proceed()
						}
					}
				}
				if do_page(left_to_right, split_golden) {
					shrink(get_current_style().scale * 2)
					set_padding(2)
					button("A")
					if do_layout(top_to_bottom, split_golden) {
						button("B")
						if do_layout(right_to_left, split_golden) {
							button("C")
							button("D")
						}
					}
				}
				if do_page(left_to_right) {
					shrink(get_current_style().scale * 2)
					foreground()
					icon_section(&state.icon_section)
				}
			}
			// for i in 0..<len(panels) {
			// 	push_id(i)
			// 	if begin_panel(sort_method = panels[i], size = [2]f32{220, 160}) {
			// 		layer := current_layer().?
			// 		shrink(10)
			// 		set_width(remaining_space().x)
			// 		set_height(26)
			// 		option_slider(reflect.enum_field_names(ronin.Layer_Sort_Method), &panels[i])
			// 		set_size(remaining_space())
			// 		label(fmt.tprintf("%v\n%i\n%i", layer.sort_method, layer.index, layer.floating_index))
			// 		// label(fmt.tprint(i), align = 0.5, font_size = 20)
			// 		end_panel()
			// 	}
			// 	pop_id()
			// }

			present()
		}
	}
}
