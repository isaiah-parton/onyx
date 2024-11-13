package onyx

import "../vgo"
import "core:fmt"
import "core:math"
import "core:math/linalg"

Panel_Info :: struct {
	title:          string,
	position, size: Maybe([2]f32),
}

Panel :: struct {
	layer:         ^Layer,
	box:           Box,
	move_offset:   [2]f32,
	last_min_size: [2]f32,
	min_size:      [2]f32,
	moving:        bool,
	resizing:      bool,
	resize_offset: [2]f32,
	is_snapped:    bool,
	non_snapped_size: [2]f32,
	fade:          f32,
	can_move:      bool,
	can_resize:    bool,
	dead:          bool,
}

create_panel :: proc(id: Id) -> Maybe(^Panel) {
	for i in 0 ..< len(global_state.panels) {
		if global_state.panels[i] == nil {
			global_state.panels[i] = Panel{}
			global_state.panel_map[id] = &global_state.panels[i].?
			return &global_state.panels[i].?
		}
	}
	return nil
}

begin_panel :: proc(
	position: Maybe([2]f32) = nil,
	size: Maybe([2]f32) = nil,
	axis: Axis = .Y,
	loc := #caller_location,
) -> bool {

	MIN_SIZE :: [2]f32{100, 100}

	id := hash(loc)
	push_id(id)

	panel, ok := global_state.panel_map[id]
	if !ok {
		panel = create_panel(id).? or_return

		position := position.? or_else get_next_panel_position()
		size := size.? or_else MIN_SIZE
		panel.box = {position, position + size}

		panel.can_move = true
		panel.can_resize = true
	}

	push_stack(&global_state.panel_stack, panel)

	if panel.moving == true {
		mouse_point := mouse_point()
		panel.moving = false
		size := panel.box.hi - panel.box.lo
		panel.box.lo = mouse_point - panel.move_offset
		panel.box.hi = panel.box.lo + size
		global_state.held_panel = panel
		draw_frames(1)
	}

	min_size := linalg.max(MIN_SIZE, panel.min_size)
	if panel.resizing {
		panel.resizing = false
		panel.box.hi = global_state.mouse_pos + panel.resize_offset
	}
	panel.box.hi = linalg.max(panel.box.hi, panel.box.lo + min_size)
	panel.box = snapped_box(panel.box)

	if panel.last_min_size != panel.min_size {
		draw_frames(1)
	}
	panel.last_min_size = panel.min_size
	panel.min_size = {}

	layer_info := Layer_Info {
		id   = id,
		kind = .Floating,
		box  = panel.box,
	}
	begin_layer(&layer_info) or_return
	panel.layer = layer_info.self

	rounding := f32(0 if panel.is_snapped else global_state.style.rounding)

	{
		object := persistent_object(panel.layer.id)
		if begin_object(object) {
			defer end_object()

			if object.variant == nil {
				object.in_state_mask = OBJECT_STATE_ALL
			}
			object.box = panel.box

			handle_object_click(object, sticky = true)


			if point_in_box(global_state.mouse_pos, object.box) {
				hover_object(object)
			}

			if .Clicked in object.state && object.click_count == 2 {
				panel.box.hi = panel.box.lo + panel.last_min_size
			} else if object_is_dragged(object, beyond = 100 if panel.is_snapped else 1) {
				if !panel.moving {
					if panel.is_snapped {
						panel.box.lo = mouse_point() - panel.non_snapped_size / 2
						panel.box.hi = mouse_point() + panel.non_snapped_size / 2
						panel.is_snapped = false
					}
					panel.non_snapped_size = box_size(panel.box)
				}
				panel.moving = true
				panel.move_offset = global_state.mouse_pos - panel.box.lo
			}

			if !panel.is_snapped {
				draw_shadow(panel.box)
			}

			vgo.fill_box(
				panel.box,
				rounding,
				paint = global_state.style.color.fg,
			)
		}
	}

	vgo.push_scissor(vgo.make_box(panel.box, rounding))
	begin_layout(box = panel.box, axis = axis) or_return
	return true
}

end_panel :: proc() {
	layout := current_layout().?
	end_layout()

	panel := current_panel()
	if panel.can_resize {
		object := persistent_object(hash("resize"))
		if begin_object(object) {
			defer end_object()
			object.box = Box{panel.box.hi - global_state.style.visual_size.y * 0.5, panel.box.hi}
			handle_object_click(object, sticky = true)
			if point_in_box(mouse_point(), object.box) {
				hover_object(object)
			}
			icon_color := global_state.style.color.substance
			if .Hovered in object.state {
				icon_color = global_state.style.color.accent
				global_state.cursor_type = .Resize_NWSE
			}
			vgo.fill_polygon(
				{
					{object.box.hi.x, object.box.lo.y},
					object.box.hi,
					{object.box.lo.x, object.box.hi.y},
				},
				paint = icon_color,
			)
			if .Pressed in object.state {
				panel.resizing = true
				if .Pressed not_in object.last_state {
					panel.resize_offset = panel.box.hi - global_state.mouse_pos
				}
			}
		}
	}

	if panel.fade > 0 {
		vgo.fill_box(panel.layer.box, 0, vgo.fade(vgo.BLACK, panel.fade * 0.15))
	}
	panel.fade = animate(
		panel.fade,
		0.15,
		panel.layer.index < global_state.last_highest_layer_index,
	)

	panel.min_size += layout.content_size + layout.spacing_size

	pop_id()
	vgo.pop_scissor()
	end_layer()
	pop_stack(&global_state.panel_stack)
}

current_panel :: proc(loc := #caller_location) -> ^Panel {
	assert(global_state.panel_stack.height > 0, "There is no current panel!", loc)
	return global_state.panel_stack.items[global_state.panel_stack.height - 1]
}

get_next_panel_position :: proc() -> [2]f32 {
	pos: [2]f32 = 100
	for i in 0 ..< len(global_state.panels) {
		if panel, ok := global_state.panels[i].?; ok {
			if pos == panel.box.lo {
				pos += 50
			}
		}
	}
	return pos
}
