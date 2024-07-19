package ui

import sapp "../sokol-odin/sokol/app"
import sg "../sokol-odin/sokol/gfx"
import sgl "../sokol-odin/sokol/gl"
import slog "../sokol-odin/sokol/log"
import sglue "../sokol-odin/sokol/glue"
import sdtx "../sokol-odin/sokol/debugtext"

import "vendor:fontstash"

import "core:runtime"
import "core:fmt"
import "core:math"
import "core:math/linalg"

MAX_IDS :: 10
MAX_LAYERS :: 100
MAX_WIDGETS :: 4000
MAX_LAYOUTS :: 100
MAX_FONTS :: 10
MAX_DRAW_STATES :: 100
MAX_LAYER_VERTICES :: 65536
MAX_LAYER_INDICES :: 65536
ATLAS_SIZE :: 4096

// Private global core instance
@private core: Core
// Stack
Stack :: struct($T: typeid, $N: int) {
	items: [N]T,
	height: int,
}
push :: proc(stack: ^Stack($T, $N), item: T) -> bool {
	if stack.height >= N {
		return false
	}
	stack.items[stack.height] = item
	stack.height += 1
	return true
}
pop :: proc(stack: ^Stack($T, $N)) {
	stack.height -= 1
}
// Input events should be localized to layers
Mouse_Button :: enum {
	Left,
	Right,
	Middle,
}
Mouse_Bits :: bit_set[Mouse_Button]
// The global core data
Core :: struct {
	view: [2]f32,

	pipeline: sg.Pipeline,
	bindings: sg.Bindings,
	pass_action: sg.Pass_Action,

	layer_list: [dynamic]^Maybe(Layer),
	layer_map: map[Id]^Maybe(Layer),
	layers: [MAX_LAYERS]Maybe(Layer),
	widgets: [MAX_WIDGETS]Maybe(Widget),

	hovered_layer,
	focused_layer: Id,

	layout_stack: Stack(Layout, MAX_LAYOUTS),
	layer_stack: Stack(^Layer, MAX_LAYERS),
	id_stack: Stack(Id, MAX_IDS),

	mouse_pos: [2]f32,
	mouse_scroll: [2]f32,
	mouse_bits, last_mouse_bits: Mouse_Bits,
	keys, last_keys: [max(sapp.Keycode)]bool,
	runes: [dynamic]rune,

	frame_cb: proc(_: rawptr),
	frame_cb_data: rawptr,

	// Draw state
	// text_selection: Text_Selection,
	// fonts: [MAX_FONTS]Maybe(Font),
	draw_states: Stack(Draw_State, MAX_DRAW_STATES),
	draw_surface: ^Draw_Surface,

	atlas: sg.Image,
}
// App descriptor
Desc :: struct {
	width,
	height: i32,
	fullscreen: bool,
	title: cstring,
	frame_cb: proc(_: rawptr),
	frame_cb_data: rawptr,
	// style: Style_Desc,
}
// Boxes
Box :: struct {
	low, high: [2]f32,
}
// Layout
Layout :: struct {
	box: Box,
}
// Layer
Layer :: struct {
	id: Id,
	box: Box,
	contents: map[Id]^Maybe(Widget),
	surface: Draw_Surface,
}
init_layer :: proc(layer: ^Layer) {
	init_draw_surface(&layer.surface)
}

view_box :: proc() -> Box {
	return Box{{}, core.view}
}

__new_layer :: proc(id: Id) -> (res: ^Maybe(Layer), ok: bool) {
	for i in 0..<MAX_LAYERS {
		if core.layers[i] == nil {
			core.layers[i] = Layer{
				id = id,
			}
			layer := &core.layers[i]
			core.layer_map[id] = &core.layers[i]
			append(&core.layer_list, layer)
			init_layer(&core.layers[i].?)
			return &core.layers[i], true
		}
	}
	return nil, false
}
begin_layer :: proc(box: Box, loc := #caller_location) {
	id := hash(loc)

	layer := core.layer_map[id] or_else (__new_layer(id) or_else panic("Out of layer!"))
	push(&core.layer_stack, &layer.?)
	core.draw_surface = &core.layer_stack.items[core.layer_stack.height - 1].surface
}
end_layer :: proc() {
	pop(&core.layer_stack)
	core.draw_surface = &core.layer_stack.items[core.layer_stack.height - 1].surface if core.layer_stack.height > 0 else nil
}

run :: proc(desc: Desc) {
	core.frame_cb = desc.frame_cb
	core.frame_cb_data = desc.frame_cb_data

	init_cb :: proc "c" () {
		context = runtime.default_context()
		
		core.view = {sapp.widthf(), sapp.heightf()}
		/*
			Initialize graphics environment
		*/
		sg.setup({
			environment = sglue.environment(),
			logger = { func = slog.func },
		})
		/*
			Initialize debug text context
		*/
		sdtx.setup(sdtx.Desc{
			logger = { func = slog.func },
			fonts = {
        0 = sdtx.font_kc853(),
        1 = sdtx.font_kc854(),
        2 = sdtx.font_z1013(),
        3 = sdtx.font_cpc(),
        4 = sdtx.font_c64(),
        5 = sdtx.font_oric(),
      },
		})
		/*
			Set up graphics pipeline
		*/
		core.pipeline = sg.make_pipeline(sg.Pipeline_Desc{
			shader = sg.make_shader(ui_shader_desc(sg.query_backend())),
			index_type = .UINT16,
			layout = {
				attrs = {
					0 = { offset = i32(offset_of(Vertex, pos)), format = .FLOAT2 },
					1 = { offset = i32(offset_of(Vertex, uv)), format = .FLOAT2 },
					2 = { offset = i32(offset_of(Vertex, col)), format = .UBYTE4N },
				},
				buffers = {
					0 = { stride = size_of(Vertex) },
				},
			},
			colors = {
				0 = {
					pixel_format = sg.Pixel_Format.RGBA8,
					write_mask = sg.Color_Mask.RGB,
					blend = {
						enabled = true,
						src_factor_rgb = sg.Blend_Factor.SRC_ALPHA,
						dst_factor_rgb = sg.Blend_Factor.ONE_MINUS_SRC_ALPHA,
					},
				},
			},
			label = "pipeline",
			cull_mode = .NONE,
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
		core.bindings.index_buffer = sg.make_buffer(sg.Buffer_Desc{
			type = .INDEXBUFFER,
			usage = .STREAM,
			size = MAX_LAYER_INDICES * size_of(u16),
		})
		core.bindings.vertex_buffers[0] = sg.make_buffer(sg.Buffer_Desc{
			type = .VERTEXBUFFER,
			usage = .STREAM,
			size = MAX_LAYER_VERTICES * size_of(Vertex),
		})
		core.bindings.fs.images[0] = sg.make_image(sg.Image_Desc{
			type = ._2D,
			pixel_format = .RGBA8,
			width = ATLAS_SIZE,
			height = ATLAS_SIZE,
			usage = .DYNAMIC,
			sample_count = 1,
		})
		core.bindings.fs.samplers[0] = sg.make_sampler(sg.Sampler_Desc{
			min_filter = .DEFAULT,
			mag_filter = .DEFAULT,
		})
	}
	frame_cb :: proc "c" () {
		context = runtime.default_context()

		if core.frame_cb != nil {
			core.frame_cb(core.frame_cb_data)
		}

		sdtx.canvas(core.view.x, core.view.y)
		sdtx.font(3)
		sdtx.pos(1, 1)
		sdtx.color3b(255, 255, 255)
		sdtx.printf("frame: %f", sapp.frame_duration())

		sg.begin_pass({
			action = core.pass_action,
			swapchain = sglue.swapchain(),
		})
		sg.apply_pipeline(core.pipeline)
		sg.apply_bindings(core.bindings)
		sg.apply_uniforms(.VS, 0, { ptr = &core.view, size = size_of(core.view) })
		// render layers
		for layer in core.layer_list {
			layer := &layer.?

			// core.bindings.vertex_buffer_offsets[0] = i32(len(layer.surface.vertices) * size_of(Vertex))
			sg.update_buffer(core.bindings.index_buffer, { 
				ptr = raw_data(layer.surface.indices), 
				size = u64(len(layer.surface.indices) * size_of(u16)),
			})
			sg.update_buffer(core.bindings.vertex_buffers[0], { 
				ptr = raw_data(layer.surface.vertices), 
				size = u64(len(layer.surface.vertices) * size_of(Vertex)),
			})
			// sg.apply_scissor_rectf(layer.box.low.x, layer.box.low.y, (layer.box.high.x - layer.box.low.x), (layer.box.high.y - layer.box.low.y), true)
			sg.draw(0, len(layer.surface.indices), 1)
			// sg.apply_scissor_rectf(0, 0, core.view.x, core.view.y, true)
		}

		sdtx.draw()

		sg.end_pass()
		sg.commit()
	}
	cleanup_cb :: proc "c" () {
		context = runtime.default_context()
		sg.destroy_buffer(core.bindings.index_buffer)
		sg.destroy_buffer(core.bindings.vertex_buffers[0])
		sg.destroy_pipeline(core.pipeline)
		sg.shutdown()
	}
	event_cb :: proc "c" (e: ^sapp.Event) {
		context = runtime.default_context()

		#partial switch e.type {
			case .MOUSE_DOWN:
			core.mouse_bits += {Mouse_Button(e.mouse_button)}
			case .MOUSE_UP:
			core.mouse_bits -= {Mouse_Button(e.mouse_button)}
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
			// sapp.quit()
			case .RESIZED:
			core.view = {sapp.widthf(), sapp.heightf()}
		}
	}

	sapp.run(sapp.Desc{
		init_cb = init_cb,
		frame_cb = frame_cb,
		cleanup_cb = cleanup_cb,
		event_cb = event_cb,

		width = desc.width,
		height = desc.height,
		fullscreen = desc.fullscreen,
		window_title = desc.title,
	})
}