package onyx

import "base:runtime"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:mem"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import "core:sys/windows"
import "core:time"
import "tedit"
import "vendor:fontstash"
import "vendor:glfw"
import "vendor:wgpu"

EMBED_DEFAULT_FONTS :: #config(ONYX_EMBED_FONTS, false)
FONT_PATH :: #config(ONYX_FONT_PATH, "../onyx/fonts")
MAX_IDS :: 32
MAX_LAYERS :: 100
MAX_WIDGETS :: 4000
MAX_LAYOUTS :: 100
MAX_PANELS :: 100
DEFAULT_DESIRED_FPS :: 75

Stack :: struct($T: typeid, $N: int) {
	items:  [N]T,
	height: int,
}

push_stack :: proc(stack: ^Stack($T, $N), item: T) -> bool {
	if stack.height < 0 || stack.height >= N {
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

// @(private)
core: Core

Debug_State :: struct {
	enabled, widgets, panels, layers: bool,
	delta_time:                       [dynamic]f32,
}

// The global core data
Core :: struct {
	ready:                 bool,
	window:                glfw.WindowHandle,
	debug:                 Debug_State,
	view:                  [2]f32,
	desired_fps:           int,
	// Disable frame rate limit
	disable_frame_skip:    bool,
	// Timings
	delta_time:            f32,
	last_frame_time:       time.Time,
	start_time:            time.Time,
	last_second:           time.Time,
	frames_so_far:         int,
	frames_this_second:    int,
	// Hashing
	id_stack:              Stack(Id, MAX_IDS),
	// Widgets
	widgets:               [MAX_WIDGETS]Maybe(Widget),
	widget_map:            map[Id]^Widget,
	widget_stack:          Stack(^Widget, 10),
	last_hovered_widget:   Id,
	hovered_widget:        Id,
	next_hovered_widget:   Id,
	last_focused_widget:   Id,
	focused_widget:        Id,
	dragged_widget:        Id,
	disable_widgets:       bool,
	drag_offset:           [2]f32,
	// Form
	form:                  Form,
	form_active:           bool,
	// Layout
	layout_stack:          Stack(Layout, MAX_LAYOUTS),
	active_container:      Id,
	next_active_container: Id,
	// Panels
	panels:                [MAX_PANELS]Maybe(Panel),
	panel_map:             map[Id]^Panel,
	panel_stack:           Stack(^Panel, MAX_PANELS),
	// Layers
	layers:                [MAX_LAYERS]Layer,
	layer_map:             map[Id]^Layer,
	layer_stack:           Stack(^Layer, MAX_LAYERS),
	focused_layer:         Id,
	highest_layer_index:   int,
	last_hovered_layer:    Id,
	hovered_layer:         Id,
	next_hovered_layer:    Id,
	// IO
	cursor_type:           Mouse_Cursor,
	mouse_button:          Mouse_Button,
	last_mouse_pos:        [2]f32,
	mouse_pos:             [2]f32,
	click_mouse_pos:       [2]f32,
	mouse_delta:           [2]f32,
	mouse_scroll:          [2]f32,
	mouse_bits:            Mouse_Bits,
	last_mouse_bits:       Mouse_Bits,
	keys, last_keys:       #sparse[Keyboard_Key]bool,
	runes:                 [dynamic]rune,
	visible:               bool,
	focused:               bool,
	// Style
	style:                 Style,
	// Text
	fonts:                 [MAX_FONTS]Maybe(Font),
	// Texture atlas
	atlas:                 Atlas,
	// Source boxes of user images on the texture atlas
	user_images:           [100]Maybe(Box),
	// Scratch text editor
	text_editor:           tedit.Editor,
	// Global arrays referenced by text jobs
	// their contents are transient
	glyphs:                [dynamic]Text_Job_Glyph,
	lines:                 [dynamic]Text_Job_Line,
	// Drawing
	draw_this_frame:       bool,
	draw_next_frame:       bool,
	frames:                int,
	drawn_frames:          int,
	draw_state:            Draw_State,
	// Transform matrices
	matrix_stack:          Stack(Matrix, MAX_MATRICES),
	current_matrix:        ^Matrix,
	last_matrix:           Matrix,
	matrix_index:          u32,
	// Currently bound user texture
	current_texture:       wgpu.Texture,
	// Scissors
	scissor_stack:         Stack(Scissor, 100),
	draw_calls:            [dynamic]Draw_Call,
	current_draw_call:     ^Draw_Call,
	cursors:               [Mouse_Cursor]glfw.CursorHandle,
	gfx:                   Graphics,
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

load_default_fonts :: proc() -> bool {
	DEFAULT_FONT :: "Geist-Medium.ttf"
	MONOSPACE_FONT :: "Recursive_Monospace-Medium.ttf"
	HEADER_FONT :: "Lora-Medium.ttf"
	ICON_FONT :: "remixicon.ttf"

	DEFAULT_FONT_DATA: Maybe([]u8) =
		#load("fonts/" + DEFAULT_FONT, []u8) when EMBED_DEFAULT_FONTS else nil
	MONOSPACE_FONT_DATA: Maybe([]u8) =
		#load("fonts/" + MONOSPACE_FONT, []u8) when EMBED_DEFAULT_FONTS else nil
	HEADER_FONT_DATA: Maybe([]u8) = #load("fonts/" + HEADER_FONT, []u8) when EMBED_DEFAULT_FONTS else nil
	ICON_FONT_DATA: Maybe([]u8) = #load("fonts/" + ICON_FONT, []u8) when EMBED_DEFAULT_FONTS else nil

	core.style.default_font = load_font_from_memory(
		DEFAULT_FONT_DATA.? or_else os.read_entire_file(
			fmt.tprintf("%s/%s", FONT_PATH, DEFAULT_FONT),
		) or_return,
	) or_return
	core.style.monospace_font = load_font_from_memory(
		MONOSPACE_FONT_DATA.? or_else os.read_entire_file(
			fmt.tprintf("%s/%s", FONT_PATH, MONOSPACE_FONT),
		) or_return,
		monospace = true,
	) or_return
	core.style.header_font = load_font_from_memory(
		HEADER_FONT_DATA.? or_else os.read_entire_file(
			fmt.tprintf("%s/%s", FONT_PATH, HEADER_FONT),
		) or_return,
	) or_return
	core.style.icon_font = load_font_from_memory(
		ICON_FONT_DATA.? or_else os.read_entire_file(
			fmt.tprintf("%s/%s", FONT_PATH, ICON_FONT),
		) or_return,
	) or_return

	return true
}

init :: proc(window: glfw.WindowHandle, style: Maybe(Style) = nil) -> bool {
	if window == nil do return false

	// Default style
	if style == nil {
		core.style.color = dark_color_scheme()
		core.style.shape = default_style_shape()
		fmt.printfln("No style provided by user, using default theme and fonts")

		if !load_default_fonts() {
			fmt.printfln("Fatal: failed to load default fonts from '%s'", FONT_PATH)
			return false
		}

	} else {
		core.style = style.?
	}

	core.window = window
	width, height := glfw.GetWindowSize(core.window)

	// Set view parameters
	core.visible = true
	core.focused = true
	core.view = {f32(width), f32(height)}
	core.last_frame_time = time.now()
	core.draw_next_frame = true
	core.start_time = time.now()

	// Create cursors
	core.cursors[.Normal] = glfw.CreateStandardCursor(glfw.ARROW_CURSOR)
	core.cursors[.Crosshair] = glfw.CreateStandardCursor(glfw.CROSSHAIR_CURSOR)
	core.cursors[.Pointing_Hand] = glfw.CreateStandardCursor(glfw.POINTING_HAND_CURSOR)
	core.cursors[.I_Beam] = glfw.CreateStandardCursor(glfw.IBEAM_CURSOR)
	core.cursors[.Resize_EW] = glfw.CreateStandardCursor(glfw.RESIZE_EW_CURSOR)
	core.cursors[.Resize_NS] = glfw.CreateStandardCursor(glfw.RESIZE_NS_CURSOR)
	core.cursors[.Resize_NESW] = glfw.CreateStandardCursor(glfw.RESIZE_NESW_CURSOR)
	core.cursors[.Resize_NWSE] = glfw.CreateStandardCursor(glfw.RESIZE_NWSE_CURSOR)

	// Set event callbacks
	glfw.SetWindowIconifyCallback(
		core.window,
		proc "c" (_: glfw.WindowHandle, _: i32) {core.visible = false},
	)
	glfw.SetWindowFocusCallback(
		core.window,
		proc "c" (_: glfw.WindowHandle, _: i32) {core.visible = true},
	)
	glfw.SetWindowMaximizeCallback(
		core.window,
		proc "c" (_: glfw.WindowHandle, _: i32) {core.visible = true},
	)
	glfw.SetScrollCallback(core.window, proc "c" (_: glfw.WindowHandle, x, y: f64) {
		core.mouse_scroll = {f32(x), f32(y)}
		core.draw_this_frame = true
		core.draw_next_frame = true
	})
	glfw.SetWindowSizeCallback(core.window, proc "c" (_: glfw.WindowHandle, width, height: i32) {
		context = runtime.default_context()
		core.draw_this_frame = true
		core.draw_next_frame = true
		core.view = {f32(width), f32(height)}
		resize_graphics(&core.gfx, int(width), int(height))
		core.draw_this_frame = true
		core.draw_next_frame = true
	})
	glfw.SetCharCallback(core.window, proc "c" (_: glfw.WindowHandle, char: rune) {
		context = runtime.default_context()
		append(&core.runes, char)
		core.draw_this_frame = true
		core.draw_next_frame = true
	})
	glfw.SetKeyCallback(core.window, proc "c" (_: glfw.WindowHandle, key, _, action, _: i32) {
		core.draw_this_frame = true
		core.draw_next_frame = true
		if key < 0 {
			return
		}
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
		core.draw_this_frame = true
	})
	glfw.SetMouseButtonCallback(
		core.window,
		proc "c" (_: glfw.WindowHandle, button, action, _: i32) {
			core.mouse_button = Mouse_Button(button)
			core.draw_this_frame = true
			core.draw_next_frame = true
			switch action {
			case glfw.PRESS:
				core.mouse_bits += {Mouse_Button(button)}
				core.click_mouse_pos = core.mouse_pos
			case glfw.RELEASE:
				core.mouse_bits -= {Mouse_Button(button)}
			}
		},
	)

	// Initialize graphics pipeline
	init_graphics(&core.gfx, core.window)

	// Init font atlas
	atlas_size: int = min(cast(int)core.gfx.device_limits.maxTextureDimension2D, MAX_ATLAS_SIZE)
	init_atlas(&core.atlas, &core.gfx, atlas_size, atlas_size)

	core.ready = true

	return true
}

// Call before each new frame
new_frame :: proc() {
	// Timings
	if !core.disable_frame_skip {
		time.sleep(
			max(
				0,
				time.Duration(time.Second) /
					time.Duration(max(core.desired_fps, DEFAULT_DESIRED_FPS)) -
				time.since(core.last_frame_time),
			),
		)
	}

	profiler_scope(.New_Frame)

	// Update timings
	now := time.now()
	core.delta_time = f32(time.duration_seconds(time.diff(core.last_frame_time, now)))
	core.last_frame_time = now
	core.frames += 1
	core.frames_so_far += 1
	if time.since(core.last_second) >= time.Second {
		core.last_second = time.now()
		core.frames_this_second = core.frames_so_far
		core.frames_so_far = 0
	}

	// Reset draw calls and draw list
	clear(&core.draw_calls)
	core.current_draw_call = nil

	// Reset draw state
	core.draw_state = {}
	core.current_texture = {}

	core.scissor_stack.height = 0
	core.matrix_stack.height = 0
	core.current_matrix = nil
	core.matrix_index = 0
	core.last_matrix = {}

	// Clear inputs
	core.last_mouse_bits = core.mouse_bits
	core.last_mouse_pos = core.mouse_pos
	core.last_keys = core.keys
	core.mouse_scroll = {}
	clear(&core.runes)

	// Clear text job arrays
	clear(&core.glyphs)
	clear(&core.lines)

	// Clear temp allocator
	free_all(context.temp_allocator)

	// Decide if this frame will be drawn
	if core.draw_next_frame {
		core.draw_next_frame = false
		core.draw_this_frame = true
	}

	// Handle window events
	glfw.PollEvents()

	// Set and reset cursor
	if core.cursor_type == .None {
		glfw.SetInputMode(core.window, glfw.CURSOR, glfw.CURSOR_HIDDEN)
	} else {
		glfw.SetInputMode(core.window, glfw.CURSOR, glfw.CURSOR_NORMAL)
		glfw.SetCursor(core.window, core.cursors[core.cursor_type])
	}
	core.cursor_type = .Normal

	if key_pressed(.Escape) {
		core.focused_widget = 0
	}

	if key_pressed(.F3) {
		core.debug.enabled = !core.debug.enabled
		core.draw_this_frame = true
	}

	// Reset stuff
	core.layer_stack.height = 0
	core.layout_stack.height = 0
	core.widget_stack.height = 0
	core.panel_stack.height = 0

	// Update layer ids
	core.highest_layer_index = 0
	core.last_hovered_layer = core.hovered_layer
	core.last_hovered_widget = core.hovered_widget
	core.last_focused_widget = core.focused_widget
	core.hovered_layer = core.next_hovered_layer
	core.next_hovered_layer = 0

	core.active_container = core.next_active_container
	core.next_active_container = 0

	if (core.mouse_bits - core.last_mouse_bits) > {} {
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
			if .Persistent not_in widget.flags {
				// Cleanup
				destroy_widget(widget)
				// Removal
				delete_key(&core.widget_map, id)
				(^Maybe(Widget))(widget)^ = nil
				// Redraw
				core.draw_this_frame = true
			}
		} else {
			widget.dead = true
		}
	}

	// Process widgets
	process_widgets()

	reset(&core.gfx)

	// For now, null paint lives at index 0
	append(&core.gfx.paints.data, Paint{kind = .Normal})

	// And glyph paint lives at index 1
	append(&core.gfx.paints.data, Paint{kind = .Atlas_Sample})

	// Default shape lives at index 0
	append(&core.gfx.shapes.data, Shape{kind = .Normal})

	// User code profiler scope
	profiler_begin_scope(.Construct)
}

// Render queued draw calls and reset draw state
render :: proc() {
	profiler_end_scope(.Construct)
	profiler_scope(.Render)

	// Render debug info rq
	if core.debug.enabled {
		if key_pressed(.F6) {
			core.disable_frame_skip = !core.disable_frame_skip
		}
		do_debug_layer()
	}

	// Update the atlas if needed
	if core.atlas.modified {
		t := time.now()
		update_atlas(&core.atlas, &core.gfx)
		core.atlas.modified = false
	}

	if core.draw_this_frame && core.visible {
		draw(&core.gfx, core.draw_calls[:])
		core.drawn_frames += 1
		core.draw_this_frame = false
	}
}

destroy :: proc() {
	if !core.ready {
		return
	}

	for _, widget in core.widget_map {
		destroy_widget(widget)
	}

	for _, &layer in core.layer_map {
		destroy_layer(layer)
	}

	for &font, f in core.fonts {
		if font, ok := font.?; ok {
			destroy_font(&font)
		}
	}

	delete(core.widget_map)
	delete(core.panel_map)
	delete(core.layer_map)
	delete(core.glyphs)
	delete(core.lines)
	delete(core.runes)
	destroy_atlas(&core.atlas)
	destroy_graphics(&core.gfx)
}

__set_clipboard_string :: proc(_: rawptr, str: string) -> bool {
	cstr := strings.clone_to_cstring(str)
	defer delete(cstr)
	glfw.SetClipboardString(core.window, cstr)
	return true
}

__get_clipboard_string :: proc(_: rawptr) -> (str: string, ok: bool) {
	str = glfw.GetClipboardString(core.window)
	ok = len(str) > 0
	return
}
