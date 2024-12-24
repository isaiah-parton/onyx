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

	buttons_active: [4]bool
	justify: onyx.Align
	checkbox_value: bool
	toggle_value: bool
	radio_value: bool
	input_value: string
	slider_values: f64 = 3
	color: vgo.Color = vgo.GOLD
	enum_value: runtime.Odin_OS_Type
	date: Maybe(onyx.Date)
	until: Maybe(onyx.Date)
	boolean_value: [onyx.Boolean_Type]bool

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
					paint = vgo.make_linear_gradient(
						box.lo,
						box.hi,
						colors().bg[0],
						colors().bg[1],
					),
				)
			}

			if begin_layer(kind = .Background) {
				defer end_layer()

				if begin_layout(placement = view_box(), padding = 50) {
					defer end_layout()

					foreground()
					calendar(&date, &until)
				}
			}

			if begin_panel(axis = .X) {
				defer end_panel()

				if begin_column_layout(size = Fixed(36)) {
					push_current_options()

					defer pop_options()
					defer end_layout()

					set_width(Percent(100))
					set_height(Percent_Of_Width(100))
					set_margin(bottom = 1)
					set_rounded_corners({})
					button("\uf578", accent = .Subtle, font_size = 20)
					button("\uf044", accent = .Subtle, font_size = 20)
					if button("\uedca", accent = .Subtle, font_size = 20).clicked {
						thread.run(proc() {
							when ODIN_OS == .Linux {
								libc.system("xdg-open \"https://github.com/isaiah-parton/onyx\"")
							} else when ODIN_OS == .Windows {
								libc.system("explorer \"https://github.com/isaiah-parton/onyx\"")
							}
						})
					}
				}


				if begin_column_layout(size = At_Least(0), padding = 20) {
					defer end_layout()

					if begin_column_layout(size = Fixed(30)) {
						defer end_layout()

						current_placement_options().align = .Center
						label("Content alignment")
					}
					if begin_row_layout(size = Fixed(30)) {
						defer end_layout()

						set_align(.Far)
						for member, i in Align {
							push_id(i)
							if tab(fmt.tprint(member), justify == member) {
								justify = member
							}
							pop_id()
						}
					}

					if begin_row_layout(
						justify = justify,
						size = Percent_Of_Remaining(25),
						padding = 10,
					) {
						defer end_layout()

						set_margin(left = 1)
						BUTTON_LABELS := [?]string{"Improvise", "Adapt", "Overcome", "Bubblegum"}
						for i in 0 ..< len(buttons_active) {
							push_id(i)
							if button(BUTTON_LABELS[i], active = buttons_active[i]).clicked {
								buttons_active[i] = !buttons_active[i]
							}
							pop_id()
						}
					}
					if begin_row_layout(
						justify = justify,
						size = Percent_Of_Remaining(33.33),
						padding = 10,
					) {
						defer end_layout()

						set_margin(left = 1)
						raw_input(
							&input_value,
							placeholder = "sample text",
						)
						button("search")
					}
					if begin_row_layout(
						justify = justify,
						size = Percent_Of_Remaining(50),
						padding = 10,
					) {
						defer end_layout()

						set_margin_all(4)
						for type, i in Boolean_Type {
							push_id(i)
							boolean(&boolean_value[type], fmt.tprint(type), type = type)
							pop_id()
						}
					}
					if begin_row_layout(
						justify = justify,
						size = Percent_Of_Remaining(100),
						padding = 10,
					) {
						defer end_layout()

						set_margin_all(4)
						slider(&slider_values, 0, 10)
						color_picker(&color)
					}
				}
			}
			present()
		}
	}
}
