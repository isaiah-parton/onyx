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
import "core:c/libc"
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
	slider_values: f64 = 3
	color: vgo.Color = vgo.GOLD
	enum_value: runtime.Odin_OS_Type
	boolean_value: [onyx.Boolean_Type]bool

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

					vgo.fill_box(layout_box(), paint = colors().field)

					set_width_fill()
					set_height_to_width()
					button("\uf578", style = .Ghost, font_size = 20)
					button("\uf044", style = .Ghost, font_size = 20)
					if button("\uedca", style = .Ghost, font_size = 20).clicked {
						libc.system("explorer \"https://github.com/isaiah-parton/onyx\"")
					}
				}

				if begin_layout(size = At_Least(0), axis = .Y, padding = 15) {
					defer end_layout()

					if begin_layout(justify = .Near, align = .Center, size = Percent(25), axis = .X) {
						defer end_layout()

						set_margin(left = 4, right = 4)
						for style, i in Button_Style {
							push_id(i)
								button(fmt.tprint(style), style = style)
							pop_id()
						}
					}
					if begin_layout(justify = .Center, align = .Center, size = Percent(25), axis = .X) {
						defer end_layout()

						raw_input(&input_value, placeholder = "sample text", decal = .Spinner)
					}
					if begin_layout(justify = .Center, axis = .X, align = .Center, size = Percent(25)) {
						defer end_layout()

						set_margin_all(4)
						for type, i in Boolean_Type {
							push_id(i)
									boolean(&boolean_value[type], fmt.tprint(type), type = type)
							pop_id()
						}
					}
					if begin_layout(justify = .Center, axis = .X, align = .Center, size = Percent(25)) {
						defer end_layout()

						set_margin_all(4)
						slider(&slider_values, 0, 10)
					}
				}
			}
			present()
		}
	}
}
