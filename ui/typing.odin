package ui

import sapp "extra:sokol-odin/sokol/app"

import "core:strings"
import "core:slice"
import "core:unicode/utf8"

Text_Selection :: struct {
	anchor,
	offset: int,
}

Text_Field :: struct {
	data: ^[dynamic]u8,
	cap: int,
	allowed,
	forbidden: string,
}
