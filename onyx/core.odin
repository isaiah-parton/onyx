package onyx

import sapp "extra:sokol-odin/sokol/app"
import sg "extra:sokol-odin/sokol/gfx"
import sgl "extra:sokol-odin/sokol/gl"
import slog "extra:sokol-odin/sokol/log"
import sglue "extra:sokol-odin/sokol/glue"
import sdtx "extra:sokol-odin/sokol/debugtext"

import "vendor:fontstash"

import "core:time"
import "base:runtime"
import "core:fmt"
import "core:strings"
import "core:math"
import "core:math/linalg"

MAX_IDS :: 10
MAX_LAYERS :: 100
MAX_WIDGETS :: 4000
MAX_LAYOUTS :: 100

MAX_TEXTURES :: 200

MAX_DRAW_CALL_VERTICES :: 65536
MAX_DRAW_CALL_INDICES :: 65536

Stack :: struct($T: typeid, $N: int) {
	items: [N]T,
	height: int,
}

push_stack :: proc(stack: ^Stack($T, $N), item: T) -> bool {
	if stack.height >= N {
		return false
	}
	stack.items[stack.height] = item
	stack.height += 1
	return true
}

pop_stack :: proc(stack: ^Stack($T, $N)) {
	stack.height -= 1
}

Keyboard_Key :: sapp.Keycode
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
	show_debug_stats: bool,

	arena: runtime.Arena,
	view: [2]f32,

	pipeline: sg.Pipeline,				// Graphics pipeline
	bindings: sg.Bindings,				// Buffer and image bindings

	layer_list: [dynamic]^Layer,					// Layers ordered by their z-index
	layer_map: map[Id]^Layer,							// Map lookup by id
	layers: [MAX_LAYERS]Maybe(Layer),			// Static allocated layer data
	widgets: [MAX_WIDGETS]Maybe(Widget),	// Static allocated widget data
	widget_map: map[Id]^Widget,

	last_hovered_widget,
	hovered_widget,
	next_hovered_widget: Id,
	last_focused_widget,
	focused_widget,
	dragged_widget: Id,

	root_layer: ^Layer,
	sort_layers: bool,
	last_top_layer,
	top_layer,
	scrolling_layer,
	last_hovered_layer,
	hovered_layer,														// The current hovered layer
	focused_layer: Id,												// The current focused layer

	layout_stack: Stack(Layout, MAX_LAYOUTS),		// The layout context stack
	layer_stack: Stack(^Layer, MAX_LAYERS),			// The layer context stack
	id_stack: Stack(Id, MAX_IDS),								// The ID context stack for compound hashing

	cursor_type: sapp.Mouse_Cursor,
	mouse_button: Mouse_Button,
	last_mouse_pos,
	mouse_pos: [2]f32,
	mouse_scroll: [2]f32,
	mouse_bits, last_mouse_bits: Mouse_Bits,
	keys, last_keys: [max(sapp.Keycode)]bool,
	runes: [dynamic]rune,

	style: Style,

	visible,
	focused: bool,
	frame_count: int,
	delta_time: f32,							// Delta time in seconds
	last_frame_time: time.Time,		// Time of last frame
	draw_this_frame,
	draw_next_frame: bool,

	fonts: [MAX_FONTS]Maybe(Font),
	current_font: int,

	textures: [MAX_TEXTURES]Maybe(Texture),
	atlas: Atlas,

	text_job: Text_Job,

	vertex_state: Vertex_State,

	path_stack: Stack(Path, 10),
	draw_call_stack: Stack(Draw_Call, MAX_DRAW_CALLS),
	current_draw_call: ^Draw_Call,
	matrix_stack: Stack(Matrix, MAX_MATRICES),
	current_matrix: ^Matrix,
}

view_box :: proc() -> Box {
	return Box{{}, core.view}
}

get_mouse_pos :: proc() -> [2]f32 {
	return core.mouse_pos
}

init :: proc () {
	// Set view parameters
	core.visible = true
	core.focused = true
	core.view = {sapp.widthf(), sapp.heightf()}
	core.last_frame_time = time.now()
	core.draw_next_frame = true
	// Set up graphics environment
	environment := sglue.environment()
	sg.setup(sg.Desc{
		environment = environment,
		logger = { func = slog.func },
	})
	// Prepare debug text context
	sdtx.setup(sdtx.Desc{
		logger = { func = slog.func },
		fonts = {
      0 = sdtx.font_cpc(),
    },
	})
	// Prepare the graphics pipeline
	core.pipeline = sg.make_pipeline(sg.Pipeline_Desc{
		shader = sg.make_shader(ui_shader_desc(sg.query_backend())),
		index_type = .UINT16,
		layout = {
			attrs = {
				0 = { offset = i32(offset_of(Vertex, pos)), format = .FLOAT3 },
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
		depth = {
			pixel_format = .DEPTH,
			compare = .GREATER_EQUAL,
			write_enabled = true,
		},
		label = "pipeline",
		cull_mode = .BACK,
	})
	// Prepare graphics buffers
	core.bindings.index_buffer = sg.make_buffer(sg.Buffer_Desc{
		type = .INDEXBUFFER,
		usage = .STREAM,
		size = MAX_DRAW_CALL_INDICES * size_of(u16),
	})
	core.bindings.vertex_buffers[0] = sg.make_buffer(sg.Buffer_Desc{
		type = .VERTEXBUFFER,
		usage = .STREAM,
		size = MAX_DRAW_CALL_VERTICES * size_of(Vertex),
	})
	core.bindings.fs.samplers[0] = sg.make_sampler(sg.Sampler_Desc{
		min_filter = .NEAREST,
		mag_filter = .NEAREST,
		wrap_u = .MIRRORED_REPEAT,
		wrap_v = .MIRRORED_REPEAT,
	})

	core.style.button_text_size = 18
	core.style.content_text_size = 16
	core.style.header_text_size = 28

	core.style.text_input_height = 30

	init_atlas(&core.atlas, ATLAS_SIZE, ATLAS_SIZE)

	fmt.println("ʕ·ᴥ·ʔ Onyx is awake and feeling great!")
}

begin_frame :: proc () {
	now := time.now()
	core.delta_time = f32(time.duration_seconds(time.diff(core.last_frame_time, now)))
	core.last_frame_time = now

	if key_pressed(.ESCAPE) {
		core.focused_widget = 0
	}

	if key_pressed(.F3) {
		core.show_debug_stats = !core.show_debug_stats
		core.draw_this_frame = true
	}

	if core.draw_next_frame {
		core.draw_next_frame = false
		core.draw_this_frame = true
	}

	if (core.mouse_pos != core.last_mouse_pos 
	|| core.mouse_bits != core.last_mouse_bits 
	|| len(core.runes) > 0
	|| core.last_focused_widget != core.focused_widget
	|| core.last_hovered_widget != core.hovered_widget) {
		core.draw_this_frame = true
		core.draw_next_frame = true
	}

	process_widgets()

	push_draw_call()
	push_matrix()
}

end_frame :: proc() {
	pop_matrix()

	sapp.set_mouse_cursor(core.cursor_type)
	core.cursor_type = sapp.Mouse_Cursor.DEFAULT
	// Process elements
	process_layers()
	// Update the atlas if needed
	if core.atlas.was_changed {
		update_atlas(&core.atlas)
		core.atlas.was_changed = false
	}
	// Display debug text
	if core.show_debug_stats {
		sdtx.canvas(core.view.x, core.view.y)
		sdtx.pos(1, 1)
		sdtx.color3b(255, 255, 255)
		sdtx.printf("time: %f\n", sapp.frame_duration())
		sdtx.printf("frame: %i\n", core.frame_count)
		sdtx.printf("hovered widget: %i\n", core.hovered_widget)
		sdtx.printf("focused widget: %i\n", core.focused_widget)
	}

	if core.draw_this_frame {
		// Normal render pass
		sg.begin_pass({
			action = sg.Pass_Action{
				colors = {
					0 = {
						load_action = .CLEAR,
						clear_value = {0, 0, 0, 1},
					},
				},
				depth = {
					load_action = .CLEAR,
				},
			},
			swapchain = sglue.swapchain(),
		})

		core.bindings.fs.images[0] = core.atlas.image

		sg.apply_pipeline(core.pipeline)
		sg.apply_bindings(core.bindings)

		t := -core.view.y / 2
		b := core.view.y / 2
		l := -core.view.x / 2
		r := core.view.x / 2
		f := f32(0)
		n := f32(1)
		
		rl := r - l
		tb := t - b
		fn := f - n

		projection_matrix: Matrix = {
			2 / rl, 0, 			0, 				-(r + l) / rl,
			0, 			2 / tb, 0, 				-(t + b) / tb,
			0, 			0, 			-2 / fn,	-(f + n) / fn,
			0, 			0, 			0, 				1,
		}

		sg.apply_uniforms(.VS, 0, { 
			ptr = &projection_matrix,
			size = size_of(Matrix),
		})

		// render layers
		for c in 0..<core.draw_call_stack.height {
			call := &core.draw_call_stack.items[c]

			sg.update_buffer(core.bindings.index_buffer, { 
				ptr = raw_data(call.indices), 
				size = u64(len(call.indices) * size_of(u16)),
			})
			sg.update_buffer(core.bindings.vertex_buffers[0], { 
				ptr = raw_data(call.vertices), 
				size = u64(len(call.vertices) * size_of(Vertex)),
			})

			// sg.apply_scissor_rectf(
			// 	call.scissor_box.lo.x, 
			// 	call.scissor_box.lo.y, 
			// 	(call.scissor_box.hi.x - call.scissor_box.lo.x), 
			// 	(call.scissor_box.hi.y - call.scissor_box.lo.y), 
			// 	true,
			// 	)

			sg.draw(0, len(call.indices), 1)

			// sg.apply_scissor_rectf(0, 0, core.view.x, core.view.y, true)

			clear(&call.vertices)
			clear(&call.indices)
		}
		core.frame_count += 1
		core.draw_this_frame = false
		sg.end_pass()
	}
	core.draw_call_stack.height = 0
	// Blank render pass to copy framebuffers
	sg.begin_pass(sg.Pass{
		action = sg.Pass_Action{
			colors = {
				0 = {
					load_action = .LOAD,
					store_action = .STORE,
				},
			},
			depth = {
				load_action = .LOAD,
				store_action = .STORE,
			},
		},
		swapchain = sglue.swapchain(),
	})
	if core.show_debug_stats {
		sdtx.draw()
	}
	sg.end_pass()
	sg.commit()

	// Reset drawing system
	core.vertex_state = {}
	
	// Reset root layer
	core.root_layer = nil
	core.last_mouse_pos = core.mouse_pos
	core.last_mouse_bits = core.mouse_bits
	clear(&core.runes)
	core.last_keys = core.keys
}

quit :: proc () {
	for &widget in core.widgets {
		if widget, ok := widget.?; ok {
			free_all(widget.allocator)
		}
	}

	sg.destroy_buffer(core.bindings.index_buffer)
	sg.destroy_buffer(core.bindings.vertex_buffers[0])
	sg.destroy_pipeline(core.pipeline)
	sg.shutdown()

	fmt.println("ʕ-ᴥ-ʔ Onyx went to sleep peacefully.")
}

handle_event :: proc (e: ^sapp.Event) {
	#partial switch e.type {

		case .FOCUSED, .SUSPENDED:
		core.focused = true

		case .UNFOCUSED, .RESUMED:
		core.focused = false

		case .ICONIFIED:
		core.visible = false

		case .RESTORED:
		core.visible = true

		case .MOUSE_DOWN:
		core.mouse_bits += {Mouse_Button(e.mouse_button)}
		core.mouse_button = Mouse_Button(e.mouse_button)
		
		case .MOUSE_UP:
		core.mouse_bits -= {Mouse_Button(e.mouse_button)}
		
		case .MOUSE_MOVE:
		core.mouse_pos = {e.mouse_x, e.mouse_y}
		
		case .MOUSE_SCROLL:
		core.mouse_scroll = {e.scroll_x, e.scroll_y}
		
		case .KEY_DOWN:
		core.keys[e.key_code] = true
		if e.key_repeat {
			core.last_keys[e.key_code] = false
		}
		
		case .KEY_UP:
		core.keys[e.key_code] = false
		
		case .CHAR:
		append(&core.runes, rune(e.char_code))
		
		case .QUIT_REQUESTED:
		// sapp.quit()
		
		case .RESIZED:
		core.view = {sapp.widthf(), sapp.heightf()}
		core.draw_next_frame = true
	}
}

key_down :: proc(key: Keyboard_Key) -> bool {
	return core.keys[key]
}
key_pressed :: proc(key: Keyboard_Key) -> bool {
	return core.keys[key] && !core.last_keys[key]
}
key_released :: proc(key: Keyboard_Key) -> bool {
	return core.last_keys[key] && !core.keys[key]
}

mouse_down :: proc(button: Mouse_Button) -> bool {
	return button in core.mouse_bits
}
mouse_pressed :: proc(button: Mouse_Button) -> bool {
	return core.mouse_bits - core.last_mouse_bits >= {button}
}
mouse_released :: proc(button: Mouse_Button) -> bool {
	return core.last_mouse_bits - core.mouse_bits >= {button}
}

set_clipboard_string :: proc(_: rawptr, str: string) -> bool {
	cstr := strings.clone_to_cstring(str)
	defer delete(cstr)
	sapp.set_clipboard_string(cstr)
	return true
}
get_clipboard_string :: proc(_: rawptr) -> (str: string, ok: bool) {
	cstr := sapp.get_clipboard_string()
	if cstr == nil {
		return
	}
	str = string(cstr)
	ok = true
	return
}
