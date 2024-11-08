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
	Enter         = glfw.KEY_ENTER,
	Backspace     = glfw.KEY_BACKSPACE,
	Delete        = glfw.KEY_DELETE,
	Left          = glfw.KEY_LEFT,
	Right         = glfw.KEY_RIGHT,
	Up            = glfw.KEY_UP,
	Down          = glfw.KEY_DOWN,
	Home          = glfw.KEY_HOME,
	End           = glfw.KEY_END,
	F1            = glfw.KEY_F1,
	F2            = glfw.KEY_F2,
	F3            = glfw.KEY_F3,
	F4            = glfw.KEY_F4,
	F5            = glfw.KEY_F5,
	F6            = glfw.KEY_F6,
	F7            = glfw.KEY_F7,
	F8            = glfw.KEY_F8,
	F9            = glfw.KEY_F9,
	F10           = glfw.KEY_F10,
	F11           = glfw.KEY_F11,
	F12           = glfw.KEY_F12,
	A             = glfw.KEY_A,
	B             = glfw.KEY_B,
	C             = glfw.KEY_C,
	D             = glfw.KEY_D,
	E             = glfw.KEY_E,
	F             = glfw.KEY_F,
	G             = glfw.KEY_G,
	H             = glfw.KEY_H,
	I             = glfw.KEY_I,
	J             = glfw.KEY_J,
	K             = glfw.KEY_K,
	L             = glfw.KEY_L,
	M             = glfw.KEY_M,
	N             = glfw.KEY_N,
	O             = glfw.KEY_O,
	P             = glfw.KEY_P,
	Q             = glfw.KEY_Q,
	R             = glfw.KEY_R,
	S             = glfw.KEY_S,
	T             = glfw.KEY_T,
	U             = glfw.KEY_U,
	V             = glfw.KEY_V,
	W             = glfw.KEY_W,
	X             = glfw.KEY_X,
	Y             = glfw.KEY_Y,
	Z             = glfw.KEY_Z,
	Zero          = glfw.KEY_0,
	One           = glfw.KEY_1,
	Two           = glfw.KEY_2,
	Three         = glfw.KEY_3,
	Four          = glfw.KEY_4,
	Five          = glfw.KEY_5,
	Six           = glfw.KEY_6,
	Seven         = glfw.KEY_7,
	Eight         = glfw.KEY_8,
	Nine          = glfw.KEY_9,
}

Mouse_Cursor :: enum {
	None,
	Normal,
	Crosshair,
	Pointing_Hand,
	Resize_NS,
	Resize_EW,
	Resize_NESW,
	Resize_NWSE,
	I_Beam,
	Loading,
}

key_down :: proc(key: Keyboard_Key) -> bool {
	return global_state.keys[key]
}

key_pressed :: proc(key: Keyboard_Key) -> bool {
	return global_state.keys[key] && !global_state.last_keys[key]
}

key_released :: proc(key: Keyboard_Key) -> bool {
	return global_state.last_keys[key] && !global_state.keys[key]
}

mouse_down :: proc(button: Mouse_Button) -> bool {
	return button in global_state.mouse_bits
}

mouse_pressed :: proc(button: Mouse_Button) -> bool {
	return (global_state.mouse_bits - global_state.last_mouse_bits) >= {button}
}

mouse_released :: proc(button: Mouse_Button) -> bool {
	return (global_state.last_mouse_bits - global_state.mouse_bits) >= {button}
}
