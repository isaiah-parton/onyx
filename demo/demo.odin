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

FILLER_TEXT :: `1. In the beginning was the Word, and the Word was with God, and the Word was God.  2. The same was in the beginning with God.  3. All things were made by him; and without him was not any thing made that was made.  4. In him was life; and the life was the light of men.  5. And the light shineth in darkness; and the darkness comprehended it not.`

Section :: enum {
	Button,
	Boolean,
	Menu,
	Analog,
	Text,
	Chart,
	Grid,
}

State :: struct {
	button_section:  Button_Section_State,
	boolean_section: Boolean_Section_State,
	graph_section:   Graph_Section_State,
	text_section:    Text_Section_State,
	analog_section:  Analog_Section_State,
	current_section: Section,
}

Boolean_Section_State :: struct {
	types: [onyx.Boolean_Type]bool,
}

boolean_section :: proc(state: ^Boolean_Section_State) {
	using onyx
	for type, i in Boolean_Type {
		push_id(i)
		boolean(&state.types[type], fmt.tprint(type), type = type)
		pop_id()
		space(10)
	}
}

Analog_Section_State :: struct {
	slider_value: f32,
}

analog_section :: proc(state: ^Analog_Section_State) {
	using onyx
	set_width(0)
	set_height(0)
	slider(&state.slider_value, 0, 100)
	space(20)
	progress_bar(state.slider_value / 100.0)
	space(20)
	dial(state.slider_value / 100.0)
	space(20)
	pie({33, 15, 52}, 100, {vgo.RED, vgo.GREEN, vgo.BLUE})
}

Button_Section_State :: struct {}

button_section :: proc(state: ^Button_Section_State) {
	using onyx
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
	set_width(0)
	if button("Delayed", delay = 0.75).clicked {

	}
}

Text_Section_State :: struct {
	text:           string,
	multiline_text: string,
}

text_section :: proc(state: ^Text_Section_State) {
	using onyx
	set_width(200)
	set_height(30)
	raw_input(&state.text, placeholder = "placeholder")
	space(10)
	set_height(100)
	raw_input(&state.multiline_text, placeholder = "placeholder", is_multiline = true)
}

Graph_Section_State :: struct {
	displayed_data: [20]f32,
	displayed_low:  f32,
	displayed_high: f32,
	time_range: [2]f32,
	data:           [20]f32,
	old_data:       [20]f32,
	low:            f32,
	high:           f32,
	color:          vgo.Color,
	show_points:    bool,
	show_crosshair: bool,
	snap_crosshair: bool,
	style:          onyx.Line_Chart_Fill_Style,
}

graph_section :: proc(state: ^Graph_Section_State) {
	using onyx
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
		range_slider(&state.time_range.x, &state.time_range.y, 0, 20)
		end_layout()
	}
	space(10)
	set_size(remaining_space())

	low := state.displayed_low - 2
	high := state.displayed_high + 2
	median := (low + high) / 2
	if begin_graph(
		time_range = state.time_range,
		value_range = {low, high},
		offset = {0, median * -30},
		show_crosshair = state.show_crosshair,
		snap_crosshair = state.snap_crosshair,
	) {
		curve_line_chart(state.old_data[:], vgo.fade(state.color, 0.5), fill_style = .None)
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
		if abs(difference) > 0.01 {
			draw_frames(2)
		}
	}
	state.displayed_low += (state.low - state.displayed_low) * 10 * vgo.frame_time()
	state.displayed_high += (state.high - state.displayed_high) * 10 * vgo.frame_time()
}

randomize_graphs :: proc(state: ^Graph_Section_State) {
	modifier: f32 = rand.float32_range(-1, 1)
	state.low = 0
	state.high = 0
	state.old_data = state.data
	last_value := rand.float32_range(-5, 5)
	for i in 0 ..< len(state.data) {
		value := last_value + rand.float32_range(-2, 2)
		state.data[i] = value
		state.low = min(state.low, value)
		state.high = max(state.high, value)
		last_value = value
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

			set_next_box(view_box())

			if begin_layer(kind = .Background) {

				if begin_layout(side = .Left) {

					shrink(100)

					vgo.fill_box(current_layout().?.box, 10, style().color.foreground)

					shrink(30)

					set_rounded_corners(ALL_CORNERS)

					set_height(remaining_space().y)
					set_width(200)
					if begin_layout(.Top) {
						set_height(26)

						for section, i in Section {
							set_rounded_corners(vstack_corners(i, len(Section)))
							push_id(i)
							text, _ := strings.replace_all(
								fmt.tprint(section),
								"_",
								" ",
								allocator = context.temp_allocator,
							)
							if button(text, active = state.current_section == section).clicked {
								state.current_section = section
							}
							space(1)
							pop_id()
						}

						end_layout()
					}

					space(20)

					set_width(remaining_space().x)
					if begin_layout(.Top) {
						shrink(10)

						#partial switch state.current_section {
						case .Button:
							button_section(&state.button_section)
						case .Boolean:
							boolean_section(&state.boolean_section)
						case .Analog:
							analog_section(&state.analog_section)
						case .Text:
							text_section(&state.text_section)
						case .Chart:
							graph_section(&state.graph_section)
						}

						end_layout()
					}


					end_layout()
				}

				end_layer()
			}

			present()
		}
	}
}
