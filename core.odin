package ui

import sapp "extra:sokol-odin/sokol/app"
import sg "extra:sokol-odin/sokol/gfx"
import sgl "extra:sokol-odin/sokol/gl"
import slog "extra:sokol-odin/sokol/log"
import sglue "extra:sokol-odin/sokol/glue"
import sdtx "extra:sokol-odin/sokol/debugtext"

import "vendor:fontstash"

import "core:time"
import "core:runtime"
// import "core:funtime"
import "core:fmt"
import "core:strings"
import "core:math"
import "core:math/linalg"

MAX_IDS :: 10
MAX_LAYERS :: 100
MAX_WIDGETS :: 4000
MAX_LAYOUTS :: 100
MAX_FONTS :: 10
MAX_PATHS :: 10
MAX_DRAW_STATES :: 100
MAX_LAYER_VERTICES :: 65536
MAX_LAYER_INDICES :: 65536
ATLAS_SIZE :: 4096

Keyboard_Key :: sapp.Keycode
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
	arena: runtime.Arena,
	view: [2]f32,

	pipeline: sg.Pipeline,				// Graphics pipeline
	bindings: sg.Bindings,				// Buffer and image bindings
	pass_action: sg.Pass_Action,	// 

	layer_list: [dynamic]^Layer,					// Layers ordered by their z-index
	layer_map: map[Id]^Layer,							// Map lookup by id
	layers: [MAX_LAYERS]Maybe(Layer),			// Static allocated layer data
	widgets: [MAX_WIDGETS]Maybe(Widget),	// Static allocated widget data
	widget_map: map[Id]^Widget,

	last_hovered_widget,
	hovered_widget,
	next_hovered_widget: Id,

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

	text_selection: Text_Selection,
	
	draw_surface: Maybe(^Draw_Surface),
	paths: Stack(Path, MAX_PATHS),
	atlas: Atlas,
	style: Style,

	delta_time: f32,							// Delta time in seconds
	last_frame_time: time.Time,		// Time of last frame
	draw_this_frame,
	draw_next_frame: bool,
}

view_box :: proc() -> Box {
	return Box{{}, core.view}
}

get_mouse_pos :: proc() -> [2]f32 {
	return core.mouse_pos
}

init :: proc () {
	// Set view parameters
	core.view = {sapp.widthf(), sapp.heightf()}
	core.last_frame_time = time.now()
	// Set up graphics environment
	sg.setup({
		environment = sglue.environment(),
		logger = { func = slog.func },
	})
	// Prepare debug text context
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
	// Prepare the graphics pipeline
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
		depth = {
			compare = .LESS_EQUAL,
			write_enabled = true,
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
	// Prepare graphics buffers
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
	core.bindings.fs.samplers[0] = sg.make_sampler(sg.Sampler_Desc{
		min_filter = .NEAREST,
		mag_filter = .NEAREST,
		wrap_u = .MIRRORED_REPEAT,
		wrap_v = .MIRRORED_REPEAT,
	})
	// Initialize the font atlas
	init_atlas(&core.atlas, ATLAS_SIZE, ATLAS_SIZE)
}

begin_frame :: proc () {
	context = runtime.default_context()
	now := time.now()
	core.delta_time = f32(time.duration_seconds(time.diff(core.last_frame_time, now)))
	core.last_frame_time = now
}

end_frame :: proc() {
	sapp.set_mouse_cursor(core.cursor_type)
	core.cursor_type = sapp.Mouse_Cursor.DEFAULT
	// Process elements
	process_layers()
	process_widgets()
	// Display debug text
	sdtx.canvas(core.view.x, core.view.y)
	sdtx.font(3)
	sdtx.pos(1, 1)
	sdtx.color3b(255, 255, 255)
	sdtx.printf("frame: %f", sapp.frame_duration())
	// Update the atlas if needed
	if core.atlas.was_changed {
		core.atlas.was_changed = false
		update_atlas(&core.atlas)
	}
	// Draw
	if core.draw_this_frame {
		sg.begin_pass({
			action = core.pass_action,
			swapchain = sglue.swapchain(),
		})
		core.bindings.fs.images[0] = core.atlas.image
		sg.apply_pipeline(core.pipeline)
		sg.apply_bindings(core.bindings)
		tex: Tex = {texSize = core.view}
		sg.apply_uniforms(.VS, 0, { ptr = &tex, size = size_of(Tex) })
		// render layers
		for layer in core.layer_list {
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
			clear_draw_surface(&layer.surface)
		}
		sdtx.draw()
		sg.end_pass()
		sg.commit()
	} else if core.draw_next_frame {
		core.draw_next_frame = false
		core.draw_this_frame = true
	}
	// Reset root layer
	core.root_layer = nil
	core.last_mouse_bits = core.mouse_bits
	core.last_keys = core.keys
}

quit :: proc () {
	context = runtime.default_context()

	for &widget in core.widgets {
		if widget, ok := widget.?; ok {
			free_all(widget.allocator)
		}
	}

	sg.destroy_buffer(core.bindings.index_buffer)
	sg.destroy_buffer(core.bindings.vertex_buffers[0])
	sg.destroy_pipeline(core.pipeline)
	sg.shutdown()

	fmt.println("[ui] Cleaned up")
}

handle_event :: proc (e: ^sapp.Event) {
	context = runtime.default_context()

	#partial switch e.type {
		case .MOUSE_DOWN:
		core.mouse_bits += {Mouse_Button(e.mouse_button)}
		core.mouse_button = Mouse_Button(e.mouse_button)
		case .MOUSE_UP:
		core.mouse_bits -= {Mouse_Button(e.mouse_button)}
		case .MOUSE_MOVE:
		core.last_mouse_pos = core.mouse_pos
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

set_clipboard_string :: proc(str: string) {
	cstr := strings.clone_to_cstring(str)
	defer delete(cstr)
	sapp.set_clipboard_string(cstr)
}