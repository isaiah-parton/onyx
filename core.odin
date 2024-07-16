package ui

import app "../sokol-odin/sokol/app"
import gfx "../sokol-odin/sokol/gfx"
import gl "../sokol-odin/sokol/gl"
import log "../sokol-odin/sokol/log"
import glue "../sokol-odin/sokol/glue"

import "core:runtime"

// Private global core instance
@private core: Core
// Input events should be localized to layers
Mouse_Button :: enum {
	Left,
	Right,
	Middle,
}
Mouse_Bits :: bit_set[Mouse_Button]
// The global core data
Core :: struct {
	pipeline: gfx.Pipeline,
	bind: gfx.Bindings,
	pass_action: gfx.Pass_Action,

	layer_list: [dynamic]int,
	// layouts: [MAX_LAYOUTS]Layout,
	layout_idx: int,

	mouse_pos: [2]f32,
	mouse_scroll: [2]f32,
	mouse_bits, last_mouse_bits: Mouse_Bits,

	keys, last_keys: [max(app.Keycode)]bool,
	runes: [dynamic]rune,
}
// Boxes
Box :: struct {
	low, high: [2]f32,
}
// Layout
Layout :: struct {
	// contents: [dynamic]Element,
	box: Box,
}

init :: proc(width, height: i32, title: cstring, fullscreen: bool = false) {
	init_cb :: proc "c" () {
		context = runtime.default_context()
		gfx.setup({
			environment = glue.environment(),
			logger = { func = log.func },
		})
		core.pipeline = gfx.make_pipeline(gfx.Pipeline_Desc{
			shader = gfx.make_shader(shader_desc(gfx.query_backend())),
			index_type = .UINT16,
			layout = {
				attrs = {

				},
			},
		})
		core.pass_action = {
			colors = {
				0 = {
					load_action = .CLEAR,
					clear_value = {0, 0, 0, 1},
				},
			},
		}

		core.bind.index_buffer = gfx.make_buffer(gfx.Buffer_Desc{
			type = .INDEXBUFFER,
			usage = .STREAM,

		})
		core.bind.ver
	}
	frame_cb :: proc "c" () {
		context = runtime.default_context()

		gfx.begin_pass({
			action = core.pass_action,
			swapchain = glue.swapchain(),
		})
		gfx.apply_pipeline(core.pipeline)
		gfx.apply_bindings(core.bind)
		// render layers

		gfx.end_pass()
		gfx.commit()
	}
	cleanup_cb :: proc "c" () {
		context = runtime.default_context()

		gfx.shutdown()
	}
	event_cb :: proc "c" (e: ^app.Event) {
		context = runtime.default_context()

		#partial switch e.type {
			case .MOUSE_DOWN:
			core.mouse_bits += {Mouse_Button(e.mouse_button)}
			case .MOUSE_UP:
			core.mouse_bits += {Mouse_Button(e.mouse_button)}
			case .MOUSE_MOVE:
			core.mouse_pos = {e.mouse_x, e.mouse_y}
			case .MOUSE_SCROLL:
			core.mouse_scroll = {e.scroll_x, e.scroll_y}
			case .KEY_DOWN:
			core.keys[e.key_code] = true
			case .KEY_UP:
			core.keys[e.key_code] = false
			case .CHAR:
			append(&core.runes, rune(e.char_code))
			case .QUIT_REQUESTED:
			// app.quit()
		}
	}

	app.run(app.Desc{
		init_cb = init_cb,
		frame_cb = frame_cb,
		cleanup_cb = cleanup_cb,
		event_cb = event_cb,

		width = width,
		height = height,
		fullscreen = fullscreen,
		window_title = title,

		swap_interval = 16,
	})
}