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
	dismissed:     bool,
	resize_offset: [2]f32,
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

begin_panel :: proc(info: Panel_Info, loc := #caller_location) -> bool {

	MIN_SIZE :: [2]f32{100, 100}

	id := hash(loc)
	panel, ok := global_state.panel_map[id]
	if !ok {
		panel = create_panel(id).? or_return

		position := info.position.? or_else get_next_panel_position()
		size := info.size.? or_else MIN_SIZE
		panel.box = {position, position + size}

		panel.can_move = true
		panel.can_resize = true
	}

	// Push to stack
	push_stack(&global_state.panel_stack, panel)

	push_id(id)

	if panel.moving == true {
		panel.moving = false
		size := panel.box.hi - panel.box.lo
		panel.box.lo = global_state.mouse_pos - panel.move_offset
		panel.box.hi = panel.box.lo + size

		global_state.draw_next_frame = true
	}

	// Handle panel transforms
	min_size := linalg.max(MIN_SIZE, panel.min_size)
	if panel.resizing {
		panel.resizing = false
		panel.box.hi = global_state.mouse_pos + panel.resize_offset
	}
	panel.box.hi = linalg.max(panel.box.hi, panel.box.lo + min_size)
	panel.box = snapped_box(panel.box)

	// Reset min_size to be calculated again
	if panel.last_min_size != panel.min_size {
		global_state.draw_this_frame = true
	}
	panel.last_min_size = panel.min_size
	panel.min_size = {}

	// Begin the panel layer
	layer_info := Layer_Info {
		id   = id,
		kind = .Floating,
		box  = panel.box,
	}
	begin_layer(&layer_info) or_return
	panel.layer = layer_info.self

	vgo.push_scissor(vgo.make_box(panel.box, global_state.style.rounding))

	// Background
	{
		object := persistent_object(panel.layer.id)
		if begin_object(object) {
			defer end_object()

			if object.variant == nil {
				object.in_state_mask = OBJECT_STATE_ALL
			}
			object.box = panel.box

			handle_object_click(object, sticky = true)

			draw_shadow(object.box)
			vgo.fill_box(object.box, paint = global_state.style.color.fg)

			if point_in_box(global_state.mouse_pos, object.box) {
				hover_object(object)
			}

			if .Pressed in object.state {
				panel.moving = true
				panel.move_offset = global_state.mouse_pos - panel.box.lo
			}
		}
	}

	// The content layout box
	inner_box := panel.box

	return true
}

end_panel :: proc() {

	panel := current_panel()
	// Resizing
	if panel.can_resize {
		object := persistent_object(hash("resize"))
		if object.variant == nil {
			object.variant = Button{
				object = object
			}
		}
		button := &object.variant.(Button)
		if begin_object(button) {
			defer end_object()
			button.box = Box{panel.box.hi - global_state.style.visual_size.y * 0.5, panel.box.hi}
			handle_object_click(button, sticky = true)
			button_behavior(button)
			if .Hovered in button.state {
				global_state.cursor_type = .Resize_NWSE
			}
			icon_color := vgo.blend(
				global_state.style.color.substance,
				global_state.style.color.content,
				0.5,
			)
			vgo.fill_polygon(
				{
					{button.box.hi.x, button.box.lo.y},
					button.box.hi,
					{button.box.lo.x, button.box.hi.y},
				},
				paint = icon_color,
			)
			if .Pressed in button.state {
				panel.resizing = true
				if .Pressed not_in button.last_state {
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

	layout := current_layout().?
	panel.min_size += layout.content_size + layout.spacing_size

	pop_id()
	vgo.pop_scissor()
	end_layer()
	pop_stack(&global_state.panel_stack)
}

@(deferred_out = __panel)
panel :: proc(info: Panel_Info, loc := #caller_location) -> bool {
	return begin_panel(info, loc)
}

@(private)
__panel :: proc(ok: bool) {
	if ok {
		end_panel()
	}
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
