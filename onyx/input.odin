package onyx

import "vendor:glfw"

Mouse_Button :: enum {
	Left = glfw.MOUSE_BUTTON_LEFT,
	Right = glfw.MOUSE_BUTTON_RIGHT,
	Middle = glfw.MOUSE_BUTTON_MIDDLE,
}

Mouse_Bits :: bit_set[Mouse_Button]

Keyboard_Key :: enum {
	Tab = glfw.KEY_TAB,
	Space = glfw.KEY_SPACE,
	Left_Control = glfw.KEY_LEFT_CONTROL,
	Left_Alt = glfw.KEY_LEFT_ALT,
	Left_Super = glfw.KEY_LEFT_SUPER,
	Left_Shift = glfw.KEY_RIGHT_SHIFT,
	Right_Control = glfw.KEY_RIGHT_CONTROL,
	Right_Alt = glfw.KEY_RIGHT_ALT,
	Right_Super = glfw.KEY_RIGHT_SUPER,
	Right_Shift = glfw.KEY_RIGHT_SHIFT,
	Menu = glfw.KEY_MENU,
	Escape = glfw.KEY_ESCAPE,
	F3 = glfw.KEY_F3,
	Enter = glfw.KEY_ENTER,
	Backspace = glfw.KEY_BACKSPACE,
	Delete = glfw.KEY_DELETE,
	Left = glfw.KEY_LEFT,
	Right = glfw.KEY_RIGHT,
	Up = glfw.KEY_UP,
	Down = glfw.KEY_DOWN,
	A = glfw.KEY_A,
	V = glfw.KEY_V,
	C = glfw.KEY_C,
	X = glfw.KEY_X,
	Z = glfw.KEY_Z,
	Y = glfw.KEY_Y,
	Home = glfw.KEY_HOME,
	End = glfw.KEY_END,
}

Mouse_Cursor :: enum {
	Normal = glfw.ARROW_CURSOR,
	Pointing_Hand = glfw.POINTING_HAND_CURSOR,
	Resize_NS = glfw.RESIZE_NS_CURSOR,
	Resize_EW = glfw.RESIZE_EW_CURSOR,
	Resize_NESW = glfw.RESIZE_NESW_CURSOR,
	Resize_NWSE = glfw.RESIZE_NWSE_CURSOR,
	I_Beam = glfw.IBEAM_CURSOR,
}