package onyx

Panel_Info :: struct {
	title: string,
	position,
	size: Maybe([2]f32),
}

Panel :: struct {
	layer: ^Layer,
	position,
	size: [2]f32,

	move_offset: [2]f32,
	moving,
	resizing: bool,

	can_move,
	can_resize: bool,

	dead: bool,
}

create_panel :: proc(id: Id) -> Maybe(^Panel) {
	for i in 0..<len(core.panels) {
		if core.panels[i] == nil {
			core.panels[i] = Panel{}
			core.panel_map[id] = &core.panels[i].?
			return &core.panels[i].?
		}
	}
	return nil
}

begin_panel :: proc(info: Panel_Info, loc := #caller_location) {

	id := hash(loc)
	panel, ok := core.panel_map[id]
	if !ok {
		panel = create_panel(id).? or_else panic("Out of panels!")
		panel.position = info.position.? or_else get_next_panel_position()
		panel.size = info.size.? or_else [2]f32{240, 180}
	}

	if panel.moving == true {
		if mouse_released(.Left) {
			panel.moving = false
		}
		panel.position = core.mouse_pos - panel.move_offset
		core.draw_next_frame = true
	}

	box: Box = {
		panel.position,
		panel.position + panel.size,
	}

	begin_layer({
		id = id,
		box = box,
	})

	layer := current_layer()
	panel.layer = layer

	// Background
	draw_box_fill(box, core.style.color.foreground)
	draw_box_stroke(box, 1, core.style.color.substance)

	// Title bar
	if info.title != "" {
		title_box := cut_box_top(&box, 25)
		draw_box_fill({{title_box.lo.x, title_box.hi.y - 1}, title_box.hi}, core.style.color.substance)
		draw_text({title_box.lo.x + 5, (title_box.hi.y + title_box.lo.y) / 2}, {
			text = info.title,
			font = core.style.fonts[.Regular],
			size = 18,
			align_v = .Middle,
		}, core.style.color.content)

		// Dragging
		if .Hovered in layer.state && point_in_box(core.mouse_pos, title_box) {
			if mouse_pressed(.Left) {
				panel.moving = true
				panel.move_offset = core.mouse_pos - panel.position
			}
		}
	}

	
}

end_panel :: proc() {
	end_layer()
}

get_next_panel_position :: proc() -> [2]f32 {
	pos: [2]f32 = 100
	for i in 0..<len(core.panels) {
		if panel, ok := core.panels[i].?; ok {
			if pos == panel.position {
				pos += 50
			}
		}
	}
	return pos
}
