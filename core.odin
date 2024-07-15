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


}

init :: proc(width, height: i32, title: cstring, fullscreen: bool = false) {
	init_cb :: proc "c" () {
		context = runtime.default_context()
		gfx.setup({
			environment = glue.environment(),
			logger = { func = log.func },
		})
		core.pipeline = gfx.make_pipeline({
			shader = gfx.make_shader({}),
			index_type = .UINT16,
			layout = {
				attrs = {

				},
			},
		})
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
	})
}