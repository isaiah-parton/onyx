package onyx

import sapp "extra:sokol-odin/sokol/app"
import sdtx "extra:sokol-odin/sokol/debugtext"
import sg "extra:sokol-odin/sokol/gfx"
import sgl "extra:sokol-odin/sokol/gl"
import sglue "extra:sokol-odin/sokol/glue"
import slog "extra:sokol-odin/sokol/log"

import "vendor:fontstash"

import "base:runtime"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:slice"
import "core:strings"
import "core:time"

MAX_IDS :: 10
MAX_LAYERS :: 100
MAX_WIDGETS :: 4000
MAX_LAYOUTS :: 100
MAX_PANELS :: 100

MAX_TEXTURES :: 200

MAX_VERTICES :: 65536
MAX_INDICES :: 65536

Stack :: struct($T: typeid, $N: int) {
	items:  [N]T,
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

inject_stack :: proc(stack: ^Stack($T, $N), at: int, item: T) -> bool {
	if at == stack.height {
		return push_stack(stack, item)
	}
	copy(stack.items[at + 1:], stack.items[at:])
	stack.items[at] = item
	stack.height += 1
	return true
}

clear_stack :: proc(stack: ^Stack($T, $N)) {
	stack.height = 0
}

Keyboard_Key :: sapp.Keycode

// Private global core instance
@(private)
core: Core

// Input events should be localized to layers
Mouse_Button :: enum {
	Left,
	Right,
	Middle,
}

Mouse_Bits :: bit_set[Mouse_Button]

Debug_State :: struct {
	enabled, widgets, panels, layers: bool,
}

// The global core data
Core :: struct {
	debug:                                                                Debug_State,
	arena:                                                                runtime.Arena,
	view:                                                                 [2]f32,
	pipeline:                                                             sg.Pipeline,
	limits:                                                               sg.Limits,
	layers:                                                               [MAX_LAYERS]Layer,
	layer_map:                                                            map[Id]^Layer,
	highest_layer:                                                        int,
	widgets:                                                              [MAX_WIDGETS]Maybe(
		Widget,
	),
	widget_map:                                                           map[Id]^Widget,
	disable_widgets:                                                      bool,
	panels:                                                               [MAX_PANELS]Maybe(Panel),
	panel_map:                                                            map[Id]^Panel,
	last_hovered_widget, hovered_widget, next_hovered_widget:             Id,
	last_focused_widget, focused_widget, dragged_widget:                  Id,
	last_hovered_layer, hovered_layer, next_hovered_layer, focused_layer: Id,
	widget_stack:                                                         Stack(^Widget, 10),
	layout_stack:                                                         Stack(
		Layout,
		MAX_LAYOUTS,
	),
	layer_stack:                                                          Stack(
		^Layer,
		MAX_LAYERS,
	),
	panel_stack:                                                          Stack(
		^Panel,
		MAX_PANELS,
	),
	highest_layer_index:                                                  int,
	id_stack:                                                             Stack(Id, MAX_IDS),
	cursor_type:                                                          sapp.Mouse_Cursor,
	mouse_button:                                                         Mouse_Button,
	last_mouse_pos, mouse_pos:                                            [2]f32,
	mouse_scroll:                                                         [2]f32,
	mouse_bits, last_mouse_bits:                                          Mouse_Bits,
	keys, last_keys:                                                      [max(sapp.Keycode)]bool,
	runes:                                                                [dynamic]rune,
	style:                                                                Style,
	visible, focused:                                                     bool,
	frame_count:                                                          int,
	delta_time:                                                           f32, // Delta time in seconds
	last_frame_time, start_time:                                          time.Time, // Time of last frame
	draw_this_frame, draw_next_frame:                                     bool,
	glyphs:                                                               [dynamic]Text_Job_Glyph,
	lines:                                                                [dynamic]Text_Job_Line,
	fonts:                                                                [MAX_FONTS]Maybe(Font),
	current_font:                                                         int,
	font_atlas:                                                           Atlas,
	user_images:                                                          [300]Maybe(Image),
	vertex_state:                                                         Vertex_State,
	path_stack:                                                           Stack(Path, 10),
	draw_list:                                                            Draw_List,
	draw_calls:                                                           [MAX_DRAW_CALLS]Draw_Call,
	draw_call_count:                                                      int,
	current_draw_call:                                                    ^Draw_Call,
	matrix_stack:                                                         Stack(
		Matrix,
		MAX_MATRICES,
	),
	current_matrix:                                                       ^Matrix,
}

view_box :: proc() -> Box {
	return Box{{}, core.view}
}

get_mouse_pos :: proc() -> [2]f32 {
	return core.mouse_pos
}

init :: proc() {

	// Set view parameters
	core.visible = true
	core.focused = true
	core.view = {sapp.widthf(), sapp.heightf()}
	core.last_frame_time = time.now()
	core.draw_next_frame = true
	core.start_time = time.now()

	// Set up graphics environment
	environment := sglue.environment()
	sg.setup(sg.Desc{environment = environment, logger = {func = slog.func}})

	// Query hardware limitations
	core.limits = sg.query_limits()

	// Prepare debug text context
	sdtx.setup(sdtx.Desc{logger = {func = slog.func}, fonts = {0 = sdtx.font_cpc()}})

	// Prepare the graphics pipeline
	core.pipeline = sg.make_pipeline(
		sg.Pipeline_Desc {
			shader = sg.make_shader(ui_shader_desc(sg.query_backend())),
			index_type = .UINT16,
			layout = {
				attrs = {
					0 = {offset = i32(offset_of(Vertex, pos)), format = .FLOAT3},
					1 = {offset = i32(offset_of(Vertex, uv)), format = .FLOAT2},
					2 = {offset = i32(offset_of(Vertex, col)), format = .UBYTE4N},
				},
				buffers = {0 = {stride = size_of(Vertex)}},
			},
			colors = {
				0 = {
					pixel_format = sg.Pixel_Format.RGBA8,
					write_mask = sg.Color_Mask.RGB,
					blend = sg.Blend_State {
						enabled = true,
						src_factor_rgb = .SRC_ALPHA,
						dst_factor_rgb = .ONE_MINUS_SRC_ALPHA,
					},
				},
			},
			depth = {pixel_format = .DEPTH, compare = .GREATER_EQUAL, write_enabled = true},
			label = "pipeline",
			cull_mode = .BACK,
		},
	)

	// Init font atlas
	max_atlas_size := int(core.limits.max_image_size_2d)
	atlas_size: int = min(max_atlas_size, MAX_ATLAS_SIZE)
	init_atlas(&core.font_atlas, atlas_size, atlas_size)

	init_draw_list(&core.draw_list)

	// Default style
	core.style.color = dark_color_scheme()
	core.style.shape = default_style_shape()
}

begin_frame :: proc() {
	// Timings
	now := time.now()
	core.delta_time = f32(time.duration_seconds(time.diff(core.last_frame_time, now)))
	core.last_frame_time = now

	if key_pressed(.ESCAPE) {
		core.focused_widget = 0
	}

	if key_pressed(.F3) {
		core.debug.enabled = !core.debug.enabled
		core.draw_this_frame = true
	}

	// Decide if this frame will be drawn
	if core.draw_next_frame {
		core.draw_next_frame = false
		core.draw_this_frame = true
	}

	// Decide if the next frame will be drawn
	if (core.mouse_pos != core.last_mouse_pos ||
		   core.mouse_bits != core.last_mouse_bits ||
		   len(core.runes) > 0 ||
		   core.last_focused_widget != core.focused_widget ||
		   core.last_hovered_widget != core.hovered_widget) {
		core.draw_this_frame = true
		core.draw_next_frame = true
	}

	// Tab/shift-tab selection
	if key_pressed(.TAB) {
		widget_list: [dynamic]^Widget
		defer delete(widget_list)

		for id, &widget in core.widget_map {
			if widget.is_field {
				append(&widget_list, widget)
			}
		}

		sort_proc :: proc(i, j: ^Widget) -> bool {
			return i.box.lo.y < j.box.lo.y || i.box.lo.x < j.box.lo.x
		}

		if key_down(.LEFT_SHIFT) {
			slice.reverse_sort_by(widget_list[:], sort_proc)
		} else {
			slice.sort_by(widget_list[:], sort_proc)
		}

		for widget, w in widget_list {
			if widget.id == core.focused_widget {
				core.focused_widget = widget_list[(w + 1) % len(widget_list)].id
				break
			}
		}
	}

	// Process widgets
	process_widgets()

	// Reset draw calls
	core.draw_call_count = 0

	// Push initial draw call and matrix
	push_matrix()
}

end_frame :: proc() {
	pop_matrix()

	// Display debug text
	if core.debug.enabled {
		sdtx.canvas(core.view.x, core.view.y)

		sdtx.color3b(255, 255, 255)

		sdtx.printf("frame %i\n", core.frame_count)
		sdtx.color3b(170, 170, 170)
		sdtx.printf("\ttime: %f\n", sapp.frame_duration())
		sdtx.printf("\tdraw calls: %i/%i\n", core.draw_call_count, MAX_DRAW_CALLS)
		sdtx.color3b(255, 255, 255)

		sdtx.move_y(1)

		sdtx.printf("%c Layers (L)\n", '-' if core.debug.layers else '+')
		if key_pressed(.L) do core.debug.layers = !core.debug.layers
		if core.debug.layers {
			sdtx.color3b(170, 170, 170)
			__debug_print_layer :: proc(layer: ^Layer, depth: int = 0) {
				sdtx.putc('H' if .Hovered in layer.state else '_')
				sdtx.putc('F' if .Focused in layer.state else '_')
				for i in 0 ..< depth {
					sdtx.putc('\t')
				}
				sdtx.printf("\t{:i} ({}) ({})\n", layer.id, layer.kind, layer.z_index)
				for child in layer.children {
					__debug_print_layer(child, depth + 1)
				}
			}
			for _, layer in core.layer_map {
				if layer.parent == nil {
					__debug_print_layer(layer, 0)
				}
			}
			sdtx.color3b(255, 255, 255)
		}

		sdtx.move_y(1)

		sdtx.printf("%c Widgets (W)\n", '-' if core.debug.widgets else '+')
		if key_pressed(.W) do core.debug.widgets = !core.debug.widgets
		if core.debug.widgets {
			sdtx.color3b(170, 170, 170)
			for id, &widget in core.widget_map {
				sdtx.putc('H' if .Hovered in widget.state else '_')
				sdtx.putc('F' if .Focused in widget.state else '_')
				sdtx.putc('P' if .Pressed in widget.state else '_')
				sdtx.printf(" {:i}\n", widget.id)
			}
			sdtx.color3b(255, 255, 255)
		}

		sdtx.move_y(1)

		sdtx.printf("%c Panels (P)\n", '-' if core.debug.panels else '+')
		if key_pressed(.P) do core.debug.panels = !core.debug.panels
		if core.debug.panels {
			sdtx.color3b(170, 170, 170)
			for id, &panel in core.panel_map {
				sdtx.printf(" {}\n", panel.box)
			}
			sdtx.color3b(255, 255, 255)
		}
	}

	sapp.set_mouse_cursor(core.cursor_type)
	core.cursor_type = sapp.Mouse_Cursor.DEFAULT

	// Update layer ids
	core.highest_layer_index = 0
	core.last_hovered_layer = core.hovered_layer
	core.hovered_layer = core.next_hovered_layer
	core.next_hovered_layer = 0

	if mouse_pressed(.Left) {
		core.focused_layer = core.hovered_layer
	}

	// core.last_focused_layer = core.focused_layer

	// Purge layers
	for id, &layer in core.layer_map {
		if layer.dead {

			when ODIN_DEBUG {
				fmt.printf("[ui] Deleted layer %x\n", layer.id)
			}

			// Move other layers down by one z index
			for i in 0 ..< len(core.layers) {
				other_layer := &core.layers[i]
				if other_layer.id == 0 do continue
				if other_layer.z_index > layer.z_index {
					other_layer.z_index -= 1
				}
			}

			// Remove from parent's children
			for &child, c in layer.children {
				child.parent = nil
			}
			delete(layer.children)
			remove_layer_parent(layer)

			// Remove from map
			delete_key(&core.layer_map, id)

			// Free slot in array
			layer.id = 0

			core.draw_next_frame = true
		} else {
			layer.last_state = layer.state
			layer.state = {}
			layer.dead = true
		}
	}
	// Free unused widgets
	for id, widget in core.widget_map {
		if widget.dead {
			when ODIN_DEBUG {
				fmt.printf("[core] Deleted widget %x\n", id)
			}

			if err := free_all(widget.allocator); err != .None {
				fmt.printf("[core] Error freeing widget data: %v\n", err)
			}

			delete_key(&core.widget_map, id)
			(transmute(^Maybe(Widget))widget)^ = nil
			core.draw_this_frame = true
		} else {
			widget.dead = true
		}
	}

	// Update the atlas if needed
	if core.font_atlas.modified {
		update_atlas(&core.font_atlas)
		core.font_atlas.modified = false
	}

	if core.draw_this_frame {
		// First things first ima upload all my data
		sg.apply_bindings(core.draw_list.bindings)
		sg.update_buffer(
			core.draw_list.bindings.index_buffer,
			{
				ptr = raw_data(core.draw_list.indices),
				size = u64(len(core.draw_list.indices) * size_of(u16)),
			},
		)
		sg.update_buffer(
			core.draw_list.bindings.vertex_buffers[0],
			{
				ptr = raw_data(core.draw_list.vertices),
				size = u64(len(core.draw_list.vertices) * size_of(Vertex)),
			},
		)

		// Normal render pass
		sg.begin_pass(
			{
				action = sg.Pass_Action {
					colors = {0 = {load_action = .CLEAR, clear_value = {0, 0, 0, 1}}},
					depth = {load_action = .CLEAR},
				},
				swapchain = sglue.swapchain(),
			},
		)
		sg.apply_pipeline(core.pipeline)

		// Set view bounds
		t := f32(0)
		b := f32(core.view.y)
		l := f32(0)
		r := f32(core.view.x)
		n := f32(1000)
		f := f32(-1000)

		// Thank you linalg!
		projection_matrix := linalg.matrix_ortho3d(l, r, b, t, n, f)

		// Apply projection matrix
		sg.apply_uniforms(.VS, 0, {ptr = &projection_matrix, size = size_of(projection_matrix)})

		// Render draw calls
		slice.sort_by(core.draw_calls[:core.draw_call_count], proc(i, j: Draw_Call) -> bool {
			return i.index < j.index
		})
		for &call in core.draw_calls[:core.draw_call_count] {
			bindings := core.draw_list.bindings
			bindings.fs.images[0] = call.texture
			sg.apply_bindings(bindings)

			// frag_uniforms := Frag_Uniforms{}
			// sg.apply_uniforms(.FS, 0, {ptr = &frag_uniforms, size = size_of(Frag_Uniforms)})

			// Apply scissor
			sg.apply_scissor_rectf(
				call.clip_box.lo.x,
				call.clip_box.lo.y,
				(call.clip_box.hi.x - call.clip_box.lo.x),
				(call.clip_box.hi.y - call.clip_box.lo.y),
				true,
			)

			// Draw elements
			sg.draw(call.elem_offset, call.elem_count, 1)

			// Reset scissor
			sg.apply_scissor_rectf(0, 0, core.view.x, core.view.y, true)
		}
		if core.debug.enabled {
			sdtx.draw()
		}
		sg.end_pass()
		sg.commit()

		core.frame_count += 1
		core.draw_this_frame = false
	} else {
		// Normal render pass
		sg.begin_pass(
			{
				action = sg.Pass_Action {
					colors = {0 = {load_action = .LOAD, store_action = .STORE}},
					depth = {load_action = .LOAD, store_action = .STORE},
				},
				swapchain = sglue.swapchain(),
			},
		)
		sg.end_pass()
	}

	clear_draw_list(&core.draw_list)
	core.draw_call_count = 0

	// Reset drawing system
	core.vertex_state = {}

	// Reset root layer
	core.last_mouse_pos = core.mouse_pos
	core.last_mouse_bits = core.mouse_bits
	clear(&core.runes)
	core.last_keys = core.keys
	core.mouse_scroll = {}

	// Clear text job arrays
	clear(&core.glyphs)
	clear(&core.lines)
}

quit :: proc() {
	// Free all dynamically allocated widget memory
	for &widget in core.widgets {
		if widget, ok := widget.?; ok {
			free_all(widget.allocator)
		}
	}

	// Free all font data
	for &font, f in core.fonts {
		if font, ok := font.?; ok {
			destroy_font(&font)
		}
	}

	// Free draw call data
	destroy_draw_list(&core.draw_list)

	// Delete maps
	delete(core.layer_map)
	delete(core.widget_map)
	delete(core.panel_map)

	// Now uninit gpu stuff
	sg.destroy_pipeline(core.pipeline)

	// Shutdown subsystems
	sdtx.shutdown()
	sg.shutdown()
}

handle_event :: proc(e: ^sapp.Event) {
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
	return (core.mouse_bits - core.last_mouse_bits) >= {button}
}

mouse_released :: proc(button: Mouse_Button) -> bool {
	return (core.last_mouse_bits - core.mouse_bits) >= {button}
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
