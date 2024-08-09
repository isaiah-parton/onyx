package onyx

Panel_Info :: struct {
	title: string,
	origin: [2]f32,
	size: [2]f32,
}

Panel :: struct {
	layer: ^Layer,
	box: Box,
}

begin_panel :: proc(info: Panel_Info, loc := #caller_location) {
	
}
end_panel :: proc() {
	
}
