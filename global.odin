package onyx

import "../vgo"
import "base:runtime"
import "core:container/small_array"
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
import "vendor:wgpu/glfwglue"

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

// @(private)
global_state: Global_State

@(private)
Global_State :: struct {
	ready:                    bool,
	window:                   glfw.WindowHandle,
	debug:                    Debug_State,
	view:                     [2]f32,
	desired_fps:              int,
	// Graphis
	instance:                 wgpu.Instance,
	device:                   wgpu.Device,
	adapter:                  wgpu.Adapter,
	surface:                  wgpu.Surface,
	surface_config:           wgpu.SurfaceConfiguration,
	// Disable frame rate limit
	disable_frame_skip:       bool,
	// Timings
	delta_time:               f32,
	last_frame_time:          time.Time,
	start_time:               time.Time,
	last_second:              time.Time,
	frames_so_far:            int,
	frames_this_second:       int,
	// Hashing
	id_stack:                 Stack(Id, MAX_IDS),
	// Objects
	transient_objects:        small_array.Small_Array(512, Object),
	objects:                  [dynamic]^Object,
	object_map:               map[Id]^Object,
	object_stack:             Stack(^Object, 128),
	last_hovered_object:      Id,
	hovered_object:           Id,
	next_hovered_object:      Id,
	last_focused_object:      Id,
	focused_object:           Id,
	dragged_object:           Id,
	disable_objects:          bool,
	drag_offset:              [2]f32,
	// Form
	form:                     Form,
	form_active:              bool,
	// Layout
	layout_array_array:       [128][dynamic]^Object,
	layout_array_count:       int,
	current_layout:           ^Layout,
	layout_stack:             Stack(^Layout, MAX_LAYOUTS),
	active_container:         Id,
	next_active_container:    Id,
	// Panels
	panels:                   [MAX_PANELS]Maybe(Panel),
	panel_map:                map[Id]^Panel,
	panel_stack:              Stack(^Panel, MAX_PANELS),
	// Layers are
	layers:                   [dynamic]^Layer,
	layer_map:                map[Id]^Layer,
	layer_stack:              Stack(^Layer, MAX_LAYERS),
	hovered_layer_index:      int,
	highest_layer_index:      int,
	last_highest_layer_index: int,
	last_hovered_layer:       Id,
	hovered_layer:            Id,
	next_hovered_layer:       Id,
	focused_layer:            Id,
	// IO
	cursor_type:              Mouse_Cursor,
	mouse_button:             Mouse_Button,
	last_mouse_pos:           [2]f32,
	mouse_pos:                [2]f32,
	click_mouse_pos:          [2]f32,
	mouse_delta:              [2]f32,
	mouse_scroll:             [2]f32,
	mouse_bits:               Mouse_Bits,
	last_mouse_bits:          Mouse_Bits,
	keys, last_keys:          #sparse[Keyboard_Key]bool,
	runes:                    [dynamic]rune,
	visible:                  bool,
	focused:                  bool,
	// Events
	events:                   [dynamic]Event,
	// Style
	style:                    Style,
	// Source boxes of user images on the texture atlas
	user_images:              [100]Maybe(Box),
	// Scratch text editor
	text_editor:              tedit.Editor,
	// Drawing
	draw_this_frame:          bool,
	draw_next_frame:          bool,
	frames:                   int,
	drawn_frames:             int,
	cursors:                  [Mouse_Cursor]glfw.CursorHandle,
}

colors :: proc() -> ^Color_Scheme {
	return &global_state.style.color
}

view_box :: proc() -> Box {
	return Box{{}, global_state.view}
}

view_width :: proc() -> f32 {
	return global_state.view.x
}

view_height :: proc() -> f32 {
	return global_state.view.y
}

load_default_fonts :: proc() -> bool {
	DEFAULT_FONT :: "Roboto-Regular"
	MONOSPACE_FONT :: "RobotoMono-Regular"
	HEADER_FONT :: "RobotoSlab-Regular"
	ICON_FONT :: "remixicon"

	DEFAULT_FONT_IMAGE :: #load(FONT_PATH + "/" + DEFAULT_FONT + ".png", []u8)
	MONOSPACE_FONT_IMAGE :: #load(FONT_PATH + "/" + MONOSPACE_FONT + ".png", []u8)
	HEADER_FONT_IMAGE :: #load(FONT_PATH + "/" + HEADER_FONT + ".png", []u8)
	ICON_FONT_IMAGE :: #load(FONT_PATH + "/" + ICON_FONT + ".png", []u8)

	DEFAULT_FONT_JSON :: #load(FONT_PATH + "/" + DEFAULT_FONT + ".json", []u8)
	MONOSPACE_FONT_JSON :: #load(FONT_PATH + "/" + MONOSPACE_FONT + ".json", []u8)
	HEADER_FONT_JSON :: #load(FONT_PATH + "/" + HEADER_FONT + ".json", []u8)
	ICON_FONT_JSON :: #load(FONT_PATH + "/" + ICON_FONT + ".json", []u8)
	global_state.style.default_font = vgo.load_font_from_slices(
		DEFAULT_FONT_IMAGE,
		DEFAULT_FONT_JSON,
	) or_return
	global_state.style.monospace_font = vgo.load_font_from_slices(
		MONOSPACE_FONT_IMAGE,
		MONOSPACE_FONT_JSON,
	) or_return
	global_state.style.header_font = vgo.load_font_from_slices(
		HEADER_FONT_IMAGE,
		HEADER_FONT_JSON,
	) or_return
	global_state.style.icon_font = vgo.load_font_from_slices(
		ICON_FONT_IMAGE,
		ICON_FONT_JSON,
	) or_return
	vgo.set_fallback_font(global_state.style.icon_font)

	return true
}

start :: proc(window: glfw.WindowHandle, style: Maybe(Style) = nil) -> bool {
	if window == nil do return false

	global_state.window = window
	width, height := glfw.GetWindowSize(global_state.window)

	global_state.visible = true
	global_state.focused = true
	global_state.view = {f32(width), f32(height)}
	global_state.last_frame_time = time.now()
	global_state.draw_next_frame = true
	global_state.start_time = time.now()

	global_state.cursors[.Normal] = glfw.CreateStandardCursor(glfw.ARROW_CURSOR)
	global_state.cursors[.Crosshair] = glfw.CreateStandardCursor(glfw.CROSSHAIR_CURSOR)
	global_state.cursors[.Pointing_Hand] = glfw.CreateStandardCursor(glfw.POINTING_HAND_CURSOR)
	global_state.cursors[.I_Beam] = glfw.CreateStandardCursor(glfw.IBEAM_CURSOR)
	global_state.cursors[.Resize_EW] = glfw.CreateStandardCursor(glfw.RESIZE_EW_CURSOR)
	global_state.cursors[.Resize_NS] = glfw.CreateStandardCursor(glfw.RESIZE_NS_CURSOR)
	global_state.cursors[.Resize_NESW] = glfw.CreateStandardCursor(glfw.RESIZE_NESW_CURSOR)
	global_state.cursors[.Resize_NWSE] = glfw.CreateStandardCursor(glfw.RESIZE_NWSE_CURSOR)

	glfw.SetWindowIconifyCallback(
		global_state.window,
		proc "c" (_: glfw.WindowHandle, _: i32) {global_state.visible = false},
	)
	glfw.SetWindowFocusCallback(
		global_state.window,
		proc "c" (_: glfw.WindowHandle, _: i32) {global_state.visible = true},
	)
	glfw.SetWindowMaximizeCallback(
		global_state.window,
		proc "c" (_: glfw.WindowHandle, _: i32) {global_state.visible = true},
	)
	glfw.SetScrollCallback(global_state.window, proc "c" (_: glfw.WindowHandle, x, y: f64) {
		global_state.mouse_scroll = {f32(x), f32(y)}
		global_state.draw_this_frame = true
		global_state.draw_next_frame = true
	})
	glfw.SetWindowSizeCallback(
		global_state.window,
		proc "c" (_: glfw.WindowHandle, width, height: i32) {
			context = runtime.default_context()

			global_state.surface_config.width = u32(width)
			global_state.surface_config.height = u32(height)
			wgpu.SurfaceConfigure(global_state.surface, &global_state.surface_config)

			global_state.view = {f32(width), f32(height)}
			global_state.draw_this_frame = true
			global_state.draw_next_frame = true
		},
	)
	glfw.SetCharCallback(global_state.window, proc "c" (_: glfw.WindowHandle, char: rune) {
		context = runtime.default_context()
		append(&global_state.runes, char)
		global_state.draw_this_frame = true
		global_state.draw_next_frame = true
	})
	glfw.SetKeyCallback(
		global_state.window,
		proc "c" (_: glfw.WindowHandle, key, _, action, _: i32) {
			global_state.draw_this_frame = true
			global_state.draw_next_frame = true
			if key < 0 {
				return
			}
			switch action {
			case glfw.PRESS:
				global_state.keys[Keyboard_Key(key)] = true
			case glfw.RELEASE:
				global_state.keys[Keyboard_Key(key)] = false
			case glfw.REPEAT:
				global_state.keys[Keyboard_Key(key)] = true
				global_state.last_keys[Keyboard_Key(key)] = false
			}
		},
	)
	glfw.SetCursorPosCallback(global_state.window, proc "c" (_: glfw.WindowHandle, x, y: f64) {
		global_state.mouse_pos = {f32(x), f32(y)}
		global_state.draw_this_frame = true
	})
	glfw.SetMouseButtonCallback(
		global_state.window,
		proc "c" (_: glfw.WindowHandle, button, action, _: i32) {
			global_state.draw_this_frame = true
			global_state.draw_next_frame = true
			switch action {
			case glfw.PRESS:
				global_state.mouse_button = Mouse_Button(button)
				global_state.mouse_bits += {Mouse_Button(button)}
				global_state.click_mouse_pos = global_state.mouse_pos
			case glfw.RELEASE:
				global_state.mouse_bits -= {Mouse_Button(button)}
			}
		},
	)

	global_state.instance = wgpu.CreateInstance()
	global_state.surface = glfwglue.GetSurface(global_state.instance, window)

	on_device :: proc "c" (
		status: wgpu.RequestDeviceStatus,
		device: wgpu.Device,
		message: cstring,
		userdata: rawptr,
	) {
		context = runtime.default_context()
		switch status {
		case .Success:
			(^Global_State)(userdata).device = device
		case .Error:
			fmt.panicf("Unable to aquire device: %s", message)
		case .Unknown:
			panic("Unknown error")
		}
	}

	on_adapter :: proc "c" (
		status: wgpu.RequestAdapterStatus,
		adapter: wgpu.Adapter,
		message: cstring,
		userdata: rawptr,
	) {
		context = runtime.default_context()
		switch status {
		case .Success:
			(^Global_State)(userdata).adapter = adapter
			info := wgpu.AdapterGetInfo(adapter)
			fmt.printfln("Using %v on %v", info.backendType, info.description)

			descriptor := vgo.device_descriptor()
			wgpu.AdapterRequestDevice(adapter, &descriptor, on_device, userdata)
		case .Error:
			fmt.panicf("Unable to acquire adapter: %s", message)
		case .Unavailable:
			panic("Adapter unavailable")
		case .Unknown:
			panic("Unknown error")
		}
	}

	wgpu.InstanceRequestAdapter(
		global_state.instance,
		&{powerPreference = .LowPower},
		on_adapter,
		&global_state,
	)
	global_state.surface_config = vgo.surface_configuration(
		global_state.device,
		global_state.adapter,
		global_state.surface,
	)
	global_state.surface_config.width = u32(width)
	global_state.surface_config.height = u32(height)
	wgpu.SurfaceConfigure(global_state.surface, &global_state.surface_config)

	vgo.start(global_state.device, global_state.surface)

	if style == nil {
		global_state.style.color = dark_color_scheme()
		global_state.style.shape = default_style_shape()
		if !load_default_fonts() {
			fmt.printfln(
				"Fatal: failed to load default fonts from '%s'",
				filepath.abs(FONT_PATH) or_else "",
			)
			return false
		}
	} else {
		global_state.style = style.?
	}

	global_state.ready = true

	return true
}

new_frame :: proc() {
	if !global_state.disable_frame_skip {
		time.sleep(
			max(
				0,
				time.Duration(time.Second) /
					time.Duration(max(global_state.desired_fps, DEFAULT_DESIRED_FPS)) -
				time.since(global_state.last_frame_time),
			),
		)
	}

	profiler_scope(.New_Frame)

	free_all(context.temp_allocator)

	now := time.now()
	global_state.delta_time = f32(
		time.duration_seconds(time.diff(global_state.last_frame_time, now)),
	)
	global_state.last_frame_time = now
	global_state.frames += 1
	global_state.frames_so_far += 1
	if time.since(global_state.last_second) >= time.Second {
		global_state.last_second = time.now()
		global_state.frames_this_second = global_state.frames_so_far
		global_state.frames_so_far = 0
	}

	if global_state.draw_next_frame {
		global_state.draw_next_frame = false
		global_state.draw_this_frame = true
	}

	reset_input()
	glfw.PollEvents()
	if global_state.cursor_type == .None {
		glfw.SetInputMode(global_state.window, glfw.CURSOR, glfw.CURSOR_HIDDEN)
	} else {
		glfw.SetInputMode(global_state.window, glfw.CURSOR, glfw.CURSOR_NORMAL)
		glfw.SetCursor(global_state.window, global_state.cursors[global_state.cursor_type])
	}
	global_state.cursor_type = .Normal

	global_state.layer_stack.height = 0
	global_state.layout_stack.height = 0
	global_state.object_stack.height = 0
	global_state.panel_stack.height = 0

	global_state.layout_array_count = 0

	global_state.active_container = global_state.next_active_container
	global_state.next_active_container = 0

	clean_up_layers()
	update_layer_references()
	clean_up_objects()
	update_object_references()

	clear(&global_state.events)

	if key_pressed(.Escape) {
		global_state.focused_object = 0
	}

	if key_pressed(.F3) {
		global_state.debug.enabled = !global_state.debug.enabled
		global_state.draw_this_frame = true
	}

	vgo.new_frame()

	profiler_begin_scope(.Construct)
}

// Render queued draw calls and reset draw state
present :: proc() {
	profiler_end_scope(.Construct)
	profiler_scope(.Render)

	when ODIN_DEBUG {
		if global_state.debug.enabled {
			if key_pressed(.F6) {
				global_state.disable_frame_skip = !global_state.disable_frame_skip
			}
			if key_pressed(.F7) {
				global_state.debug.wireframe = !global_state.debug.wireframe
			}
			draw_debug_stuff()
		}
	}

	if global_state.draw_this_frame && global_state.visible {
		vgo.present()
		global_state.drawn_frames += 1
		global_state.draw_this_frame = false
	}
}

shutdown :: proc() {
	if !global_state.ready {
		return
	}

	for _, object in global_state.object_map {
		destroy_object(object)
		free(object)
	}

	for layer in global_state.layers {
		destroy_layer(layer)
		free(layer)
	}

	for array in global_state.layout_array_array {
		delete(array)
	}

	delete(global_state.layers)
	delete(global_state.object_map)
	delete(global_state.panel_map)
	delete(global_state.layer_map)
	delete(global_state.runes)

	vgo.shutdown()
}

__set_clipboard_string :: proc(_: rawptr, str: string) -> bool {
	cstr := strings.clone_to_cstring(str)
	defer delete(cstr)
	glfw.SetClipboardString(global_state.window, cstr)
	return true
}

__get_clipboard_string :: proc(_: rawptr) -> (str: string, ok: bool) {
	str = glfw.GetClipboardString(global_state.window)
	ok = len(str) > 0
	return
}

draw_shadow :: proc(box: vgo.Box) {
	if vgo.disable_scissor() {
		vgo.box_shadow(
			move_box(box, 3),
			global_state.style.rounding,
			6,
			global_state.style.color.shadow,
		)
	}
}
