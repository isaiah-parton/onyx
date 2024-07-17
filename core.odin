package ui

import app "../sokol-odin/sokol/app"
import gfx "../sokol-odin/sokol/gfx"
import gl "../sokol-odin/sokol/gl"
import log "../sokol-odin/sokol/log"
import glue "../sokol-odin/sokol/glue"

import "core:runtime"
import "core:math"
import "core:math/linalg"

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
	bindings: gfx.Bindings,
	pass_action: gfx.Pass_Action,

	layer_list: [dynamic]int,
	layers: [MAX_LAYERS]Maybe(Layer),
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
// Layer
MAX_LAYERS :: 256
MAX_LAYER_VERTICES :: 65536
MAX_LAYER_INDICES :: 65536
Layer :: struct {
	// Buffer data
	vertices: [MAX_LAYER_VERTICES]Vertex,
	vertices_offset: int,
	indices: [MAX_LAYER_INDICES]u16,
	indices_offset: int,
}

init :: proc(width, height: i32, title: cstring, fullscreen: bool = false) {
	init_cb :: proc "c" () {
		context = runtime.default_context()
		gfx.setup({
			environment = glue.environment(),
			logger = { func = log.func },
		})
		core.pipeline = gfx.make_pipeline(gfx.Pipeline_Desc{
			shader = gfx.make_shader(ui_shader_desc(gfx.query_backend())),
			index_type = .UINT16,
			layout = {
				attrs = {
					0 = { offset = i32(offset_of(Vertex, pos)), format = gfx.Vertex_Format.FLOAT2 },
					1 = { offset = i32(offset_of(Vertex, uv)), format = gfx.Vertex_Format.FLOAT2 },
					2 = { offset = i32(offset_of(Vertex, col)), format = gfx.Vertex_Format.UBYTE4N },
				},
			},
			colors = {
				0 = {
					pixel_format = gfx.Pixel_Format.RGBA8,
					write_mask = gfx.Color_Mask.RGB,
					blend = {
						enabled = true,
						src_factor_rgb = gfx.Blend_Factor.SRC_ALPHA,
						dst_factor_rgb = gfx.Blend_Factor.ONE_MINUS_SRC_ALPHA,
					},
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
		/*
			Load the index and vertex buffers for streaming
		*/
		core.bindings.index_buffer = gfx.make_buffer(gfx.Buffer_Desc{
			type = .INDEXBUFFER,
			usage = .STREAM,
			size = MAX_LAYER_INDICES * size_of(u16),
		})
		core.bindings.vertex_buffers = gfx.make_buffer(gfx.Buffer_Desc{
			type = .VERTEXBUFFER,
			usage = .STREAM,
			size = MAX_LAYER_VERTICES * size_of(Vertex),
		})
	}
	frame_cb :: proc "c" () {
		context = runtime.default_context()

		gfx.begin_pass({
			action = core.pass_action,
			swapchain = glue.swapchain(),
		})
		gfx.apply_pipeline(core.pipeline)
		// render layers
		for i in core.layer_list {
			layer := &core.layers[i].?
			gfx.update_buffer(core.bindings.index_buffer, { ptr = &layer.indices, size = u64(layer.indices_offset * size_of(u16)) })
			gfx.update_buffer(core.bindings.index_buffer, { ptr = &layer.vertices, size = u64(layer.vertices_offset * size_of(u16)) })

			gfx.draw(0, layer.indices_offset, 1)
		}
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