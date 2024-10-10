package onyx

Form :: struct {
	first: ^Widget,
	last: ^Widget,
}

begin_form :: proc() {
	core.form_active = true
	core.form = {}
}

end_form :: proc() {
	if core.form.first != nil {
		core.form.first.prev = core.form.last
	}
	core.form_active = false

}
