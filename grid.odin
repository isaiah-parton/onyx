package onyx

Viewport :: struct {
	offset: [2]f32,
	zoom: f32,
}

begin_viewport :: proc() -> bool {

	return true
}

end_viewport :: proc() {

}
