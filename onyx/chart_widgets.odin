package onyx

import "core:math"
import "core:math/ease"
import "core:math/linalg"

Chart_Info :: struct($T: typeid) where intrinsics.type_is_numeric(T) {
	using _: Widget_Info,
}

chart :: proc(info: Chart_Info($T), loc := #caller_location) {

}
