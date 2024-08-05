package onyx

import sapp "extra:sokol-odin/sokol/app"

import "core:strings"
import "core:slice"
import "core:unicode/utf8"

Text_Edit_State :: struct {
	anchor,				// Current index in text
	offset: int,	// Offset of selection

	line_start,
	line_end: int,

	builder: ^strings.Builder,
}

Text_Edit_Action :: union {

}

Text_Edit_Action_Undo :: struct {}
Text_Edit_Action_Redo :: struct {}
Text_Edit_Action_Left :: struct {}

