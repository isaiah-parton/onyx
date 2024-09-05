package onyx

import "vendor:glfw"

import "vendor:fontstash"

import "base:runtime"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:mem"
import "core:slice"
import "core:strings"
import "core:time"

import "vendor:wgpu"

MAX_IDS :: 10
MAX_LAYERS :: 100
MAX_WIDGETS :: 4000
MAX_LAYOUTS :: 100
MAX_PANELS :: 100

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

// Private global core instance
// @(private)
core: Core

Debug_State :: struct {
	enabled, widgets, panels, layers: bool,
}

// The global core data
Core :: struct {
	window:                                                   glfw.WindowHandle,
	window_title:                                             string,
	debug:                                                    Debug_State,
	view:                                                     [2]f32,

	// Hashing
	id_stack:                                                 Stack(Id, MAX_IDS),

	// Widgets
	widgets:                                                  [MAX_WIDGETS]Maybe(Widget),
	widget_map:                                               map[Id]^Widget,
	widget_stack:                                             Stack(^Widget, 10),
	last_hovered_widget, hovered_widget, next_hovered_widget: Id,
	last_focused_widget, focused_widget, dragged_widget:      Id,
	disable_widgets:                                          bool,
	drag_offset:                                              [2]f32,

	// Layout
	layout_stack:                                             Stack(Layout, MAX_LAYOUTS),

	// Containers
	container_map:                                            map[Id]^Container,
	container_stack:                                          Stack(^Container, 200),
	active_container, next_active_container:                  Id,

	// Panels
	panels:                                                   [MAX_PANELS]Maybe(Panel),
	panel_map:                                                map[Id]^Panel,
	panel_stack:                                              Stack(^Panel, MAX_PANELS),

	// Layers
	layers:                                                   [MAX_LAYERS]Layer,
	layer_map:                                                map[Id]^Layer,
	layer_stack:                                              Stack(^Layer, MAX_LAYERS),
	focused_layer:                                            Id,
	highest_layer_index:                                      int,
	last_hovered_layer, hovered_layer, next_hovered_layer:    Id,

	// IO
	cursor_type:                                              Mouse_Cursor,
	mouse_button:                                             Mouse_Button,
	last_mouse_pos, mouse_pos:                                [2]f32,
	mouse_scroll:                                             [2]f32,
	mouse_bits, last_mouse_bits:                              Mouse_Bits,
	keys, last_keys:                                          #sparse[Keyboard_Key]bool,
	runes:                                                    [dynamic]rune,
	visible, focused:                                         bool,

	// Style
	style:                                                    Style,

	// Timings
	delta_time:                                               f32,
	last_frame_time, start_time:                              time.Time,
	render_duration:                                          time.Duration,

	// Text
	fonts:                                                    [MAX_FONTS]Maybe(Font),
	glyphs:                                                   [dynamic]Text_Job_Glyph,
	lines:                                                    [dynamic]Text_Job_Line,
	font_atlas:                                               Atlas,
	current_font:                                             int,
	user_images:                                              [100]Maybe(Image),

	// Drawing
	draw_this_frame, draw_next_frame:                         bool,
	vertex_state:                                             Vertex_State,
	current_matrix:                                           ^Matrix,
	current_texture:                                          wgpu.Texture,
	clip_stack:                                               Stack(Box, 100),
	path_stack:                                               Stack(Path, 10),
	matrix_stack:                                             Stack(Matrix, MAX_MATRICES),
	frames:                                                   int,
	drawn_frames:                                             int,
	draw_list:                                                Draw_List,
	draw_calls:                                               [MAX_DRAW_CALLS]Draw_Call,
	draw_call_count:                                          int,
	current_draw_call:                                        ^Draw_Call,
	gfx:                                                      Graphics,
	cursors:                                                  #sparse[Mouse_Cursor]glfw.CursorHandle,

	// Allocators
	scratch_allocator:                                        mem.Scratch_Allocator,
}

view_box :: proc() -> Box {
	return Box{{}, core.view}
}

get_mouse_pos :: proc() -> [2]f32 {
	return core.mouse_pos
}

view_width :: proc() -> f32 {
	return core.view.x
}

view_height :: proc() -> f32 {
	return core.view.y
}

init :: proc(width, height: i32, title: cstring = nil) {

	// Set view parameters
	core.visible = true
	core.focused = true
	core.view = {f32(width), f32(height)}
	core.last_frame_time = time.now()
	core.draw_next_frame = true
	core.start_time = time.now()

	glfw.Init()
	core.cursors[.Normal] = glfw.CreateStandardCursor(glfw.ARROW_CURSOR)
	core.cursors[.Pointing_Hand] = glfw.CreateStandardCursor(glfw.POINTING_HAND_CURSOR)
	core.cursors[.I_Beam] = glfw.CreateStandardCursor(glfw.IBEAM_CURSOR)
	glfw.WindowHint(glfw.DECORATED, true)
	glfw.WindowHint(glfw.TRANSPARENT_FRAMEBUFFER, false)
	glfw.WindowHint(glfw.VISIBLE, true)
	core.window = glfw.CreateWindow(width, height, title, nil, nil)

	glfw.SetScrollCallback(core.window, proc "c" (_: glfw.WindowHandle, x, y: f64) {
		core.mouse_scroll = {f32(x), f32(y)}
	})
	glfw.SetWindowSizeCallback(core.window, proc "c" (_: glfw.WindowHandle, width, height: i32) {
		context = runtime.default_context()
		core.draw_this_frame = true
		core.view = {f32(width), f32(height)}
		resize_graphics(&core.gfx, int(width), int(height))
	})
	glfw.SetKeyCallback(core.window, proc "c" (_: glfw.WindowHandle, key, action, _, _: i32) {
		switch action {
		case glfw.PRESS:
			core.keys[Keyboard_Key(key)] = true
		case glfw.RELEASE:
			core.keys[Keyboard_Key(key)] = false
		case glfw.REPEAT:
			core.keys[Keyboard_Key(key)] = true
			core.last_keys[Keyboard_Key(key)] = false
		}
	})
	glfw.SetCursorPosCallback(core.window, proc "c" (_: glfw.WindowHandle, x, y: f64) {
		core.mouse_pos = {f32(x), f32(y)}
	})
	glfw.SetMouseButtonCallback(
		core.window,
		proc "c" (_: glfw.WindowHandle, button, action, _: i32) {
			switch action {
			case glfw.PRESS:
				core.mouse_bits += {Mouse_Button(button)}
			case glfw.RELEASE:
				core.mouse_bits -= {Mouse_Button(button)}
			}
		},
	)

	init_graphics(&core.gfx, core.window, 4)

	// Init font atlas
	max_atlas_size := 4096
	atlas_size: int = min(max_atlas_size, MAX_ATLAS_SIZE)
	init_atlas(&core.font_atlas, &core.gfx, atlas_size, atlas_size)

	init_draw_list(&core.draw_list)

	// Default style
	core.style.color = dark_color_scheme()
	core.style.shape = default_style_shape()
}

begin_frame :: proc() {
	glfw.PollEvents()

	// Timings
	now := time.now()
	core.delta_time = f32(time.duration_seconds(time.diff(core.last_frame_time, now)))
	core.last_frame_time = now
	core.frames += 1

	if key_pressed(.Escape) {
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
	if key_pressed(.Tab) {
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

		if key_down(.Left_Shift) {
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

	// Push initial matrix
	push_matrix()
	set_texture(core.font_atlas.texture.internal)

	begin_layer({box = view_box(), sorting = .Below, kind = .Background})
	foreground()
}

end_frame :: proc() {
	end_layer()

	assert(core.clip_stack.height == 0)

	// Pop the last vertex matrix
	pop_matrix()

	// Set and reset cursor
	glfw.SetCursor(core.window, core.cursors[core.cursor_type])
	// sapp.set_mouse_cursor(core.cursor_type)
	core.cursor_type = .Normal

	// Update layer ids
	core.highest_layer_index = 0
	core.last_hovered_layer = core.hovered_layer
	core.hovered_layer = core.next_hovered_layer
	core.next_hovered_layer = 0

	core.active_container = core.next_active_container
	core.next_active_container = 0

	if mouse_pressed(.Left) {
		core.focused_layer = core.hovered_layer
	}

	// Purge layers
	for id, &layer in core.layer_map {
		if layer.dead {

			// Move other layers down by one z index
			for i in 0 ..< len(core.layers) {
				other_layer := &core.layers[i]
				if other_layer.id == 0 do continue
				if other_layer.index > layer.index {
					other_layer.index -= 1
				}
			}

			// Remove from parent's children
			for &child, c in layer.children {
				child.parent = nil
			}
			remove_layer_parent(layer)
			destroy_layer(layer)

			// Remove from map
			delete_key(&core.layer_map, id)

			// Free slot in array
			layer.id = 0

			core.draw_next_frame = true
		} else {
			layer.dead = true
		}
	}

	// Free unused widgets
	for id, widget in core.widget_map {
		if widget.dead {
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
	for id, cnt in core.container_map {
		if cnt.dead {
			delete_key(&core.container_map, id)
			free(cnt)
		} else {
			cnt.dead = true
		}
	}

	// Update the atlas if needed
	if core.font_atlas.modified {
		update_atlas(&core.font_atlas, &core.gfx)
		core.font_atlas.modified = false
	}

	if core.draw_this_frame {
		start_time := time.now()

		draw(&core.gfx, &core.draw_list, core.draw_calls[:])

		core.drawn_frames += 1
		core.draw_this_frame = false
		core.render_duration = time.since(start_time)
	}

	// Reset draw calls and draw list
	core.draw_call_count = 0
	core.current_draw_call = nil
	clear_draw_list(&core.draw_list)
	core.current_texture = {}

	// Reset vertex state
	core.vertex_state = {}

	// Reset input values
	core.last_mouse_pos = core.mouse_pos
	core.last_mouse_bits = core.mouse_bits
	core.last_keys = core.keys
	core.mouse_scroll = {}
	clear(&core.runes)

	// Clear text job arrays
	clear(&core.glyphs)
	clear(&core.lines)

	// Clear temp allocator
	free_all(context.temp_allocator)
}

uninit :: proc() {
	// Free all dynamically allocated widget memory
	for &widget in core.widgets {
		if widget, ok := widget.?; ok {
			free_all(widget.allocator)
		}
	}

	for _, &layer in core.layer_map {
		destroy_layer(layer)
	}

	// Free all font data
	for &font, f in core.fonts {
		if font, ok := font.?; ok {
			destroy_font(&font)
		}
	}

	mem.scratch_allocator_destroy(&core.scratch_allocator)

	// Destroy atlas
	destroy_atlas(&core.font_atlas)

	// Free draw call data
	destroy_draw_list(&core.draw_list)

	// Delete maps
	delete(core.layer_map)
	delete(core.widget_map)
	delete(core.panel_map)

	// Delete stuff
	delete(core.glyphs)
	delete(core.lines)
	delete(core.runes)
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
	glfw.SetClipboardString(core.window, cstr)
	return true
}

get_clipboard_string :: proc(_: rawptr) -> (str: string, ok: bool) {
	str = glfw.GetClipboardString(core.window)
	ok = len(str) > 0
	return
}
