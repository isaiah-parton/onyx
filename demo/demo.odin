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

	window := glfw.CreateWindow(1600, 900, "demo", nil, nil)
	defer glfw.DestroyWindow(window)

	onyx.start(window)
	defer onyx.shutdown()

	onyx.core.style.icon_font, _ = vgo.load_font_from_image_and_json(
		"../onyx/fonts/remixicon.png",
		"../onyx/fonts/remixicon.json",
		type = .Emoji,
	)
	defer vgo.destroy_font(&onyx.core.style.icon_font)

	onyx.core.style.default_font, _ = vgo.load_font_from_image_and_json(
		"../onyx/fonts/Roboto-Regular.png",
		"../onyx/fonts/Roboto-Regular.json",
	)
	defer vgo.destroy_font(&onyx.core.style.default_font)

	onyx.core.style.monospace_font, _ = vgo.load_font_from_image_and_json(
		"../onyx/fonts/RobotoMono-Regular.png",
		"../onyx/fonts/RobotoMono-Regular.json",
	)
	defer vgo.destroy_font(&onyx.core.style.monospace_font)

	onyx.core.style.header_font, _ = vgo.load_font_from_image_and_json(
		"../onyx/fonts/RobotoSlab-Regular.png",
		"../onyx/fonts/RobotoSlab-Regular.json",
	)
	defer vgo.destroy_font(&onyx.core.style.header_font.?)

	vgo.set_fallback_font(onyx.core.style.icon_font)

	checkbox_value: bool
	toggle_value: bool
	radio_value: bool
	input_value: string
	slider_value: f32
	color: vgo.Color = vgo.GOLD

	for {
		// Stuff
		if glfw.WindowShouldClose(onyx.core.window) {
			break
		}
		// UI demo code
		{
			using onyx
			new_frame()
			vgo.fill_box(view_box(), paint = core.style.color.background)
			if layer(&{box = view_box()}) {
				shrink_layout(100)
				foreground()
				shrink_layout(100)
				header({text = "Header \uf28d"})
				add_space(10)
				label({text = "Label"})
				add_space(10)
				divider()
				add_space(10)

				buttons := [?]Button_Info{
					make_button({text = "Button", style = .Outlined}),
					make_button({text = "Button with icon \uf578", style = .Outlined}),
					make_button({text = "\uf0d9", style = .Outlined, font_size = 20}),
				}

				if layout({side = .Top, size = buttons[0].desired_size.y}) {
					for &button in buttons {
						add_button(&button)
						add_space(10)
					}
				}

				add_space(20)
				checkbox({text = "Checkbox", state = &checkbox_value})
				add_space(20)
				radio_button({text = "Radio button", state = &radio_value})
				add_space(20)
				toggle_switch({state = &toggle_value, text = "Toggle switch"})
				add_space(20)
				string_input({value = &input_value, placeholder = "String input"})
				add_space(20)
				slider(Slider_Info(f32){value = &slider_value, format = "%.2f"})
				add_space(20)
				label({text = "Icons can be placed \uec8c anywhere within text! \uec8e"})
				add_space(20)
				color_button({value = &color, show_alpha = true, input_formats = {.HSL, .RGB, .HEX}})
			}
			present()
		}
	}
}
