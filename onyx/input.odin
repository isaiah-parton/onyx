package onyx

import "vendor:glfw"

Mouse_Button :: enum {
	Left   = glfw.MOUSE_BUTTON_LEFT,
	Right  = glfw.MOUSE_BUTTON_RIGHT,
	Middle = glfw.MOUSE_BUTTON_MIDDLE,
}

Mouse_Bits :: bit_set[Mouse_Button]

Keyboard_Key :: enum i32 {
	Tab           = glfw.KEY_TAB,
	Space         = glfw.KEY_SPACE,
	Left_Control  = glfw.KEY_LEFT_CONTROL,
	Left_Alt      = glfw.KEY_LEFT_ALT,
	Left_Super    = glfw.KEY_LEFT_SUPER,
	Left_Shift    = glfw.KEY_LEFT_SHIFT,
	Right_Control = glfw.KEY_RIGHT_CONTROL,
	Right_Alt     = glfw.KEY_RIGHT_ALT,
	Right_Super   = glfw.KEY_RIGHT_SUPER,
	Right_Shift   = glfw.KEY_RIGHT_SHIFT,
	Menu          = glfw.KEY_MENU,
	Escape        = glfw.KEY_ESCAPE,
	F1            = glfw.KEY_F1,
	F2            = glfw.KEY_F2,
	F3            = glfw.KEY_F3,
	F4            = glfw.KEY_F4,
	F5            = glfw.KEY_F5,
	F6            = glfw.KEY_F6,
	F7            = glfw.KEY_F7,
	F8            = glfw.KEY_F8,
	F9            = glfw.KEY_F9,
	F10            = glfw.KEY_F10,
	F11            = glfw.KEY_F11,
	F12            = glfw.KEY_F12,
	Enter         = glfw.KEY_ENTER,
	Backspace     = glfw.KEY_BACKSPACE,
	Delete        = glfw.KEY_DELETE,
	Left          = glfw.KEY_LEFT,
	Right         = glfw.KEY_RIGHT,
	Up            = glfw.KEY_UP,
	Down          = glfw.KEY_DOWN,
	A             = glfw.KEY_A,
	V             = glfw.KEY_V,
	C             = glfw.KEY_C,
	X             = glfw.KEY_X,
	Z             = glfw.KEY_Z,
	Y             = glfw.KEY_Y,
	Home          = glfw.KEY_HOME,
	End           = glfw.KEY_END,
	F = glfw.KEY_F,
}

Mouse_Cursor :: enum {
	Normal,
	Pointing_Hand,
	Resize_NS,
	Resize_EW,
	Resize_NESW,
	Resize_NWSE,
	I_Beam,
	Loading,
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
