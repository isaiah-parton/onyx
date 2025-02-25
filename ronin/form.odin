package ronin

Form :: struct {
	first: ^Object,
	last: ^Object,
}

begin_form :: proc() {
	global_state.form_active = true
	global_state.form = {}
}

end_form :: proc() {
	// if global_state.form.first != nil {
	// 	global_state.form.first.prev = global_state.form.last
	// }
	global_state.form_active = false

}
