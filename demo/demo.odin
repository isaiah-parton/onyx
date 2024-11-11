package demo

import vgo "../../vgo"
import onyx ".."
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

FILLER_TEXT ::
`1. In the beginning was the Word, and the Word was with God, and the Word was God.  2. The same was in the beginning with God.  3. All things were made by him; and without him was not any thing made that was made.  4. In him was life; and the life was the light of men.  5. And the light shineth in darkness; and the darkness comprehended it not.`

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

	checkbox_value: bool
	toggle_value: bool
	radio_value: bool
	input_value: string
	slider_values: [2]f32
	color: vgo.Color = vgo.GOLD
	enum_value: runtime.Odin_OS_Type

	for {
		if glfw.WindowShouldClose(window) {
			break
		}
		{
			using onyx
			new_frame()
			{
				box := view_box()
				vgo.fill_box(
					box,
					paint = vgo.make_linear_gradient(
						box.lo,
						box.hi,
						colors().bg[0],
						colors().bg[1],
					),
				)
			}
			if begin_panel(axis = .X) {
				defer end_panel()

				if begin_layout(size = Fixed(36), axis = .Y, align = .Center) {
					defer end_layout()

					button("\uf578", style = .Ghost, font_size = 18)
					button("\uf044", style = .Ghost, font_size = 18)
					button("\uEDC0", style = .Ghost, font_size = 18)
				}

				if begin_layout(size = At_Least(0), axis = .Y, padding = 30) {
					defer end_layout()

					if begin_layout(justify = .Far, align = .Center, size = Fixed(50), axis = .X) {
						defer end_layout()

						label("Label")
						for i in 1..=5 {
							push_id(i)
								button(fmt.tprintf("Button %i", i))
							pop_id()
						}
					}
					if begin_layout(justify = .Center, align = .Center, size = Fixed(50), axis = .X) {
						defer end_layout()

						label("Label")
						for i in 1..=5 {
							push_id(i)
								button(fmt.tprintf("Button %i", i))
							pop_id()
						}
					}
					if begin_layout(justify = .Near, align = .Center, size = Fixed(50), axis = .X) {
						defer end_layout()

						label("Label")
						for i in 1..=5 {
							push_id(i)
								button(fmt.tprintf("Button %i", i))
							pop_id()
						}
					}
					if begin_layout(justify = .Center, axis = .X, size = Fixed(200)) {
						defer end_layout()

						if begin_layout(axis = .Y, size = Fixed(100)) {
							defer end_layout()

							for i in 1..=5 {
								push_id(i)
									boolean(&checkbox_value, fmt.tprintf("Checkbox A%i", i))
								pop_id()
							}
						}
						if begin_layout(axis = .Y, size = Fixed(100)) {
							defer end_layout()

							for i in 1..=5 {
								push_id(i)
									boolean(&checkbox_value, fmt.tprintf("Checkbox B%i", i))
								pop_id()
							}
						}
					}
				}
			}
			present()
		}
	}
}
