package onyx

import "../vgo"
import "base:runtime"
import "core:container/small_array"
import "core:fmt"
import "core:math"
import "core:math/ease"
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

Wave_Effect :: struct {
	point: [2]f32,
	time:  f32,
}

global_state: Global_State

@(private)
Global_State :: struct {
	ready:                    bool,
	window:                   glfw.WindowHandle,
	window_x:                 i32,
	window_y:                 i32,
	window_width:             i32,
	window_height:            i32,
	debug:                    Debug_State,
	view:                     [2]f32,
	desired_fps:              int,
	instance:                 wgpu.Instance,
	device:                   wgpu.Device,
	adapter:                  wgpu.Adapter,
	surface:                  wgpu.Surface,
	surface_config:           wgpu.SurfaceConfiguration,
	disable_frame_skip:       bool,
	delta_time:               f32,
	last_frame_time:          time.Time,
	start_time:               time.Time,
	last_second:              time.Time,
	frame_duration:           time.Duration,
	frames_so_far:            int,
	frames_this_second:       int,
	id_stack:                 Stack(Id, MAX_IDS),
	objects:                  [dynamic]^Object,
	object_map:               map[Id]^Object,
	object_stack:             Stack(^Object, 128),
	object_index:             int,
	last_hovered_object:      Id,
	hovered_object:           Id,
	next_hovered_object:      Id,
	last_activated_object:    Id,
	last_focused_object:      Id,
	focused_object:           Id,
	next_focused_object:      Id,
	dragged_object:           Id,
	disable_objects:          bool,
	drag_offset:              [2]f32,
	mouse_press_point:        [2]f32,
	form:                     Form,
	form_active:              bool,
	tooltip_boxes:            [dynamic]Box,
	panels:                   [MAX_PANELS]Maybe(Panel),
	panel_map:                map[Id]^Panel,
	panel_stack:              Stack(^Panel, MAX_PANELS),
	panel_snapping:           Panel_Snap_State,
	layout_stack:             Stack(Layout, MAX_LAYOUTS),
	options_stack:            Stack(Options, MAX_LAYOUTS),
	next_box:                 Maybe(Box),
	press_on_hover:           bool,
	next_id:                  Maybe(Id),
	group_stack:              Stack(Group, 32),
	focus_next:               bool,
	layer_array:              [dynamic]^Layer,
	layer_map:                map[Id]^Layer,
	layer_stack:              Stack(^Layer, MAX_LAYERS),
	last_layer_counts:        [Layer_Sort_Method]int,
	layer_counts:             [Layer_Sort_Method]int,
	hovered_layer_index:      int,
	highest_layer_index:      int,
	last_highest_layer_index: int,
	last_hovered_layer:       Id,
	hovered_layer:            Id,
	next_hovered_layer:       Id,
	focused_layer:            Id,
	clip_stack:               Stack(Box, 128),
	current_object_clip:      Box,
	cursor_type:              Mouse_Cursor,
	mouse_button:             Mouse_Button,
	last_mouse_pos:           [2]f32,
	mouse_pos:                [2]f32,
	click_mouse_pos:          [2]f32,
	mouse_delta:              [2]f32,
	mouse_scroll:             [2]f32,
	mouse_bits:               Mouse_Bits,
	last_mouse_bits:          Mouse_Bits,
	mouse_release_time:       time.Time,
	keys, last_keys:          #sparse[Keyboard_Key]bool,
	runes:                    [dynamic]rune,
	visible:                  bool,
	focused:                  bool,
	style:                    Style,
	user_images:              [100]Maybe(Box),
	text_editor:              tedit.Editor,
	frames_to_draw:           int,
	frames:                   int,
	drawn_frames:             int,
	cursors:                  [Mouse_Cursor]glfw.CursorHandle,
}

seconds :: proc() -> f64 {
	return time.duration_seconds(time.diff(global_state.start_time, global_state.last_frame_time))
}

draw_frames :: proc(how_many: int) {
	global_state.frames_to_draw = max(global_state.frames_to_draw, how_many)
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

focus_next_object :: proc() {
	global_state.focus_next = true
}

load_default_fonts :: proc() -> bool {
	DEFAULT_FONT :: "Roboto-Regular"
	BOLD_FONT :: "Roboto-Medium"
	MONOSPACE_FONT :: "RobotoMono-Regular"
	HEADER_FONT :: "RobotoSlab-Regular"
	ICON_FONT :: "icons"

	DEFAULT_FONT_IMAGE :: #load(FONT_PATH + "/" + DEFAULT_FONT + ".png", []u8)
	BOLD_FONT_IMAGE :: #load(FONT_PATH + "/" + BOLD_FONT + ".png", []u8)
	MONOSPACE_FONT_IMAGE :: #load(FONT_PATH + "/" + MONOSPACE_FONT + ".png", []u8)
	HEADER_FONT_IMAGE :: #load(FONT_PATH + "/" + HEADER_FONT + ".png", []u8)
	ICON_FONT_IMAGE :: #load(FONT_PATH + "/" + ICON_FONT + ".png", []u8)

	DEFAULT_FONT_JSON :: #load(FONT_PATH + "/" + DEFAULT_FONT + ".json", []u8)
	BOLD_FONT_JSON :: #load(FONT_PATH + "/" + BOLD_FONT + ".json", []u8)
	MONOSPACE_FONT_JSON :: #load(FONT_PATH + "/" + MONOSPACE_FONT + ".json", []u8)
	HEADER_FONT_JSON :: #load(FONT_PATH + "/" + HEADER_FONT + ".json", []u8)
	ICON_FONT_JSON :: #load(FONT_PATH + "/" + ICON_FONT + ".json", []u8)

	global_state.style.default_font = vgo.load_font_from_slices(
		DEFAULT_FONT_IMAGE,
		DEFAULT_FONT_JSON,
	) or_return
	global_state.style.bold_font = vgo.load_font_from_slices(
		BOLD_FONT_IMAGE,
		BOLD_FONT_JSON,
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
		true,
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
		context = runtime.default_context()
		global_state.mouse_scroll = {f32(x), f32(y)}
		draw_frames(2)
	})
	glfw.SetWindowSizeCallback(
		global_state.window,
		proc "c" (_: glfw.WindowHandle, width, height: i32) {
			context = runtime.default_context()

			width := max(width, 1)
			height := max(height, 1)

			global_state.surface_config.width = u32(width)
			global_state.surface_config.height = u32(height)
			wgpu.SurfaceConfigure(global_state.surface, &global_state.surface_config)

			global_state.view = {f32(width), f32(height)}
			draw_frames(1)
		},
	)
	glfw.SetCharCallback(global_state.window, proc "c" (_: glfw.WindowHandle, char: rune) {
		context = runtime.default_context()
		append(&global_state.runes, char)
		draw_frames(2)
	})
	glfw.SetKeyCallback(
		global_state.window,
		proc "c" (_: glfw.WindowHandle, key, _, action, _: i32) {
			context = runtime.default_context()
			draw_frames(2)
			if key < 0 {
				return
			}
			switch action {
			case glfw.PRESS:
				global_state.keys[Keyboard_Key(key)] = true
				global_state.mouse_press_point = mouse_point()
			case glfw.RELEASE:
				global_state.keys[Keyboard_Key(key)] = false
			case glfw.REPEAT:
				global_state.keys[Keyboard_Key(key)] = true
				global_state.last_keys[Keyboard_Key(key)] = false
			}
		},
	)
	glfw.SetCursorPosCallback(global_state.window, proc "c" (_: glfw.WindowHandle, x, y: f64) {
		context = runtime.default_context()
		global_state.mouse_pos = {f32(x), f32(y)}
		draw_frames(2)
	})
	glfw.SetMouseButtonCallback(
		global_state.window,
		proc "c" (_: glfw.WindowHandle, button, action, _: i32) {
			context = runtime.default_context()
			draw_frames(2)
			switch action {
			case glfw.PRESS:
				global_state.mouse_button = Mouse_Button(button)
				global_state.mouse_bits += {Mouse_Button(button)}
				global_state.click_mouse_pos = global_state.mouse_pos
			case glfw.RELEASE:
				global_state.mouse_release_time = time.now()
				global_state.mouse_bits -= {Mouse_Button(button)}
			}
		},
	)

	// &{
	// 	nextInChain = &wgpu.InstanceExtras{
	// 		sType = .InstanceExtras,
	// 		backends = {.Vulkan},
	// 	},
	// }

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
	draw_frames(1)

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

	now := time.now()
	global_state.frame_duration = time.diff(global_state.last_frame_time, now)
	global_state.delta_time = f32(time.duration_seconds(global_state.frame_duration))
	global_state.last_frame_time = now
	global_state.frames += 1
	global_state.frames_so_far += 1
	if time.since(global_state.last_second) >= time.Second {
		global_state.last_second = time.now()
		global_state.frames_this_second = global_state.frames_so_far
		global_state.frames_so_far = 0
	}

	reset_input()
	glfw.PollEvents()

	global_state.layer_stack.height = 0
	global_state.object_stack.height = 0
	global_state.panel_stack.height = 0
	global_state.options_stack.items[0] = default_options()

	reset_panel_snap_state(&global_state.panel_snapping)

	global_state.object_index = 0

	clear(&global_state.debug.hovered_objects)

	update_layers()
	update_layer_references()
	clean_up_objects()
	update_object_references()

	clear(&global_state.tooltip_boxes)

	if key_pressed(.Tab) {
		cycle_object_active(1 - int(key_down(.Left_Shift)) * 2)
	}

	if key_pressed(.Escape) {
		global_state.focused_object = 0
	}

	if key_pressed(.F3) {
		global_state.debug.enabled = !global_state.debug.enabled
		draw_frames(1)
	}

	if key_pressed(.F11) {
		monitor := glfw.GetWindowMonitor(global_state.window)
		if monitor == nil {
			monitor = glfw.GetPrimaryMonitor()
			mode := glfw.GetVideoMode(monitor)
			global_state.window_x, global_state.window_y = glfw.GetWindowPos(global_state.window)
			global_state.window_width, global_state.window_height = glfw.GetWindowSize(
				global_state.window,
			)
			glfw.SetWindowMonitor(
				global_state.window,
				monitor,
				0,
				0,
				mode.width,
				mode.height,
				mode.refresh_rate,
			)
		} else {
			glfw.SetWindowMonitor(
				global_state.window,
				nil,
				global_state.window_x,
				global_state.window_y,
				global_state.window_width,
				global_state.window_height,
				0,
			)
		}
	}

	vgo.new_frame()

	global_state.id_stack.height = 0
	push_stack(&global_state.id_stack, FNV1A32_OFFSET_BASIS)

	profiler_begin_scope(.Construct)
}

cycle_object_active :: proc(increment: int = 1) {
	objects: [dynamic]^Object
	defer delete(objects)

	for object in global_state.objects {
		if .Is_Input in object.flags {
			append(&objects, object)
		}
	}

	slice.sort_by(objects[:], proc(i, j: ^Object) -> bool {
		return i.call_index < j.call_index
	})

	for i in 0 ..< len(objects) {
		objects[i].state.current -= {.Active}
		if objects[i].id == global_state.last_activated_object {
			j := i + increment
			for j < 0 do j += len(objects)
			for j >= len(objects) do j -= len(objects)
			object := objects[j]
			object.state.next += {.Active}
			object.input.editor.selection = {len(object.input.builder.buf), 0}
			break
		}
	}
}

present :: proc() {
	profiler_end_scope(.Construct)
	profiler_scope(.Render)

	when DEBUG {
		if global_state.debug.enabled {
			set_cursor(.Crosshair)
			if key_pressed(.F6) {
				global_state.disable_frame_skip = !global_state.disable_frame_skip
			}
			if key_pressed(.F7) {
				global_state.debug.wireframe = !global_state.debug.wireframe
			}
			draw_debug_stuff(&global_state.debug)
		}
	}

	if global_state.cursor_type == .None {
		glfw.SetInputMode(global_state.window, glfw.CURSOR, glfw.CURSOR_HIDDEN)
	} else {
		glfw.SetInputMode(global_state.window, glfw.CURSOR, glfw.CURSOR_NORMAL)
		glfw.SetCursor(global_state.window, global_state.cursors[global_state.cursor_type])
	}
	global_state.cursor_type = .Normal

	if global_state.frames_to_draw > 0 && global_state.visible {
		vgo.present()
		global_state.drawn_frames += 1
		global_state.frames_to_draw -= 1
	}
}

shutdown :: proc() {
	if !global_state.ready {
		return
	}

	for object in global_state.objects {
		destroy_object(object)
		free(object)
	}
	delete(global_state.objects)
	delete(global_state.object_map)

	for layer in global_state.layer_array {
		destroy_layer(layer)
		free(layer)
	}

	delete(global_state.layer_array)
	delete(global_state.panel_map)
	delete(global_state.layer_map)
	delete(global_state.runes)

	vgo.destroy_font(&global_state.style.default_font)
	vgo.destroy_font(&global_state.style.monospace_font)
	vgo.destroy_font(&global_state.style.icon_font)
	if font, ok := global_state.style.header_font.?; ok {
		vgo.destroy_font(&font)
	}

	destroy_debug_state(&global_state.debug)

	vgo.shutdown()
}

delta_time :: proc() -> f32 {
	return global_state.delta_time
}

should_close_window :: proc() -> bool {
	return bool(glfw.WindowShouldClose(global_state.window))
}

set_rounded_corners :: proc(corners: Corners) {
	current_options().radius = rounded_corners(corners)
}

user_focus_just_changed :: proc() -> bool {
	return global_state.focused_object != global_state.last_focused_object
}

set_clipboard_string :: proc(str: string) {
	cstr := strings.clone_to_cstring(str)
	defer delete(cstr)
	glfw.SetClipboardString(global_state.window, cstr)
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
		vgo.box_shadow(move_box(box, 3), global_state.style.rounding, 6, style().color.shadow)
	}
}
