package onyx

// pop_placement_options :: proc() {
// 	pop_stack(&global_state.placement_options_stack)
// }

// set_align :: proc(align: Align) {
// 	current_placement_options().align = align
// }

// set_width :: proc(size: Layout_Size) {
// 	current_placement_options().size.x = size
// }

// set_height :: proc(size: Layout_Size) {
// 	current_placement_options().size.y = size
// }

// set_margin_sides :: proc(
// 	left: Maybe(f32) = nil,
// 	right: Maybe(f32) = nil,
// 	top: Maybe(f32) = nil,
// 	bottom: Maybe(f32) = nil,
// ) {
// 	options := current_placement_options()
// 	if left, ok := left.?; ok do options.margin.x = left
// 	if top, ok := top.?; ok do options.margin.y = top
// 	if right, ok := right.?; ok do options.margin.z = right
// 	if bottom, ok := bottom.?; ok do options.margin.w = bottom
// }

// set_margin_all :: proc(amount: f32) {
// 	current_placement_options().margin = amount
// }

// set_margin :: proc {
// 	set_margin_sides,
// 	set_margin_all,
// }
