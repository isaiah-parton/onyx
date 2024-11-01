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

	onyx.core.style.default_font, _ = vgo.load_font_from_image_and_json(
		"../onyx/fonts/font.png",
		"../onyx/fonts/font.json",
	)
	defer vgo.destroy_font(&onyx.core.style.default_font)

	checkbox_value: bool
	input_value: string
	slider_value: f32

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
				button({text = "wsg ima button yo", style = Button_Style.Outlined})
				add_space(20)
				checkbox({text = "checkbox!", state = &checkbox_value})
				add_space(20)
				string_input({value = &input_value, placeholder = "bro type somethin"})
				add_space(20)
				slider(Slider_Info(f32){value = &slider_value, format = "rizz %.2f"})
			}
			present()
		}
	}
}
