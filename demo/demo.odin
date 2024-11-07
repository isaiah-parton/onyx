package demo

import vgo "../../vgo"
import onyx "../onyx"
import "base:runtime"
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
import "core:time"
import "vendor:glfw"
import "vendor:wgpu"

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

	// glfw.WindowHint(glfw.TRANSPARENT_FRAMEBUFFER, true)
	window := glfw.CreateWindow(1400, 800, "demo", nil, nil)
	defer glfw.DestroyWindow(window)

	onyx.start(window)
	defer onyx.shutdown()

	checkbox_value: bool
	toggle_value: bool
	radio_value: bool
	input_value: string
	slider_values: [2]f32
	date: Maybe(onyx.Date)
	color: vgo.Color = vgo.GOLD
	enum_value: runtime.Odin_OS_Type

	for {
		// Stuff
		if glfw.WindowShouldClose(onyx.core.window) {
			break
		}
		// UI demo code
		{
			using onyx
			new_frame()
			vgo.fill_box(view_box(), paint = vgo.make_linear_gradient(0, core.view, core.style.color.bg[0], core.style.color.bg[1]))
			if panel({}) {
				add_padding(30)
				header({text = "Header \uf28d"})
				add_space(10)
				label({text = "Label"})
				add_space(10)
				divider()
				add_space(10)

				buttons := [?]Button_Info{
					make_button({text = "Button", style = .Primary}),
					make_button({text = "Button with icon \uf578", style = .Secondary}),
					make_button({text = "\uf0d9", style = .Ghost, font_size = 20}),
					make_button({text = "Colored button", style = .Outlined, color = vgo.Color{220, 57, 57, 255}}),
				}

				if layout({side = .Top, size = buttons[2].desired_size.y}) {
					for &button in buttons {
						add_button(&button)
						add_space(10)
					}
				}

				SPACING :: 10
				add_space(SPACING)
				checkbox({text = "Checkbox", state = &checkbox_value})
				add_space(SPACING)
				radio_button({text = "Radio button", state = &radio_value})
				add_space(SPACING)
				toggle_switch({state = &toggle_value, text = "Toggle switch"})
				add_space(SPACING)
				string_input({value = &input_value, placeholder = "String input"})
				add_space(SPACING)
				slider(Slider_Info(f32){value = &slider_values[0], lo = 0, hi = 10, format = "%.1f"})
				add_space(SPACING)
				box_slider(Slider_Info(f32){value = &slider_values[1], lo = 0, hi = 10, format = "%.1f"})
				add_space(SPACING)
				label({text = "Icons can be placed \ued3c anywhere within text! \uec8e"})
				add_space(SPACING)
				color_button({value = &color, show_alpha = true})
				add_space(SPACING)
				date_picker({first = &date})
				add_space(SPACING)
				enum_selector(&enum_value)
			}
			if panel({}) {

			}
			present()
		}
	}
}
