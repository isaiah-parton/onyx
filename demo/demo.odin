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
	Basic,
	Graphs,
}

State :: struct {
	buttons_active: [4]bool,
	justify: onyx.Align,
	checkbox_value: bool,
	toggle_value: bool,
	radio_value: bool,
	input_value: string,
	slider_values: f64,
	color: vgo.Color,
	enum_value: runtime.Odin_OS_Type,
	date: Maybe(onyx.Date),
	until: Maybe(onyx.Date),
	boolean_value: bool,
	current_section: Section,
	displayed_graph_data: [20]f32,
	graph_data: [20]f32,
	graph_low: f32,
	graph_high: f32,
	graph_color: vgo.Color,
}

section_basic :: proc(state: ^State) {
	using onyx

	set_height(0)
	label("Row layout")

	space(10)

	set_width(remaining_space().x)
	set_height(24)
	if begin_layout(side = .Left) {

		set_width(0)
		set_rounded_corners(ALL_CORNERS)
		button("Add")
		space(10)
		set_rounded_corners({.Top_Left, .Bottom_Left})
		button("Select All", accent = .Outlined)
		space(1)
		set_rounded_corners({})
		button("Invert Selection", accent = .Outlined)
		space(1)
		set_rounded_corners({.Top_Right, .Bottom_Right})
		button("Filter", accent = .Outlined)

		end_layout()
	}

	space(20)

	for type, i in Boolean_Type {
		push_id(i)
			boolean(&state.boolean_value, fmt.tprint(type), type = type)
			space(10)
		pop_id()
	}

	space(10)

	set_rounded_corners(ALL_CORNERS)
	set_width(0)
	set_height(0)
	label("Text Input")
	space(4)
	set_width(200)
	set_height(30)
	raw_input(&state.input_value, placeholder = "placeholder")

	space(20)

	set_height(remaining_space().y)
	if begin_container() {
		set_width(remaining_space().x)
		set_height(34)
		set_rounded_corners(ALL_CORNERS)
		set_padding(4)
		for i in 1..=100 {
			push_id(i)
				button(fmt.tprintf("Button #%i", i), accent = .Subtle)
			pop_id()
		}

		end_container()
	}
}

section_graphs :: proc(state: ^State) {
	using onyx
	set_side(.Bottom)
	set_height(26)
	if begin_layout(.Left) {
		set_width(0)
		if button("Randomize").clicked {
			randomize_graphs(state)
		}
		space(10)
		color_picker(&state.graph_color)
		end_layout()
	}
	space(10)
	set_size(remaining_space())
	if begin_graph(30, state.graph_low - 10, state.graph_high + 10) {
		curve_graph(state.displayed_graph_data[:], state.graph_color, "USD $%.2f")

		end_graph()
	}

	for i in 0..<len(state.graph_data) {
		state.displayed_graph_data[i] += (state.graph_data[i] - state.displayed_graph_data[i]) * 10 * vgo.frame_time()
	}
}

randomize_graphs :: proc(state: ^State) {
	modifier: f32 = rand.float32_range(-1, 1)
	for i in 0..<len(state.graph_data) {
		value := f32(i) * modifier + rand.float32_range(-2, 2)
		state.graph_data[i] = value
		state.graph_low = min(state.graph_low, value)
		state.graph_high = max(state.graph_high, value)
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
	state.graph_color = vgo.GREEN
	randomize_graphs(&state)

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
				vgo.fill_box(
					box,
					paint = colors().background,
				)
			}

			set_next_box(view_box())

			if begin_layer(kind = .Background) {

				if begin_layout(side = .Left) {

					shrink(100)

					vgo.fill_box(current_layout().?.box, 10, colors().foreground)

					shrink(25)

					set_height(remaining_space().y)
					set_width(200)
					if begin_layout(.Top) {
						set_height(26)

						for section, i in Section {
							if i == 0 {
								set_rounded_corners({.Top_Left, .Top_Right})
							} else if i == len(Section) - 1 {
								set_rounded_corners({.Bottom_Left, .Bottom_Right})
							} else {
								set_rounded_corners({})
							}
							push_id(i)
								if button(fmt.tprint(section), active = state.current_section == section).clicked {
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

						shrink(20)
						switch state.current_section {
						case .Basic:
							section_basic(&state)
						case .Graphs:
							section_graphs(&state)
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
