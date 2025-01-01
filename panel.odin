package onyx

import "../vgo"
import "core:fmt"
import "core:math"
import "core:math/linalg"

Panel :: struct {
	layer:            ^Layer,
	box:              Box,
	move_offset:      [2]f32,
	last_min_size:    [2]f32,
	min_size:         [2]f32,
	moving:           bool,
	resizing:         bool,
	resize_offset:    [2]f32,
	is_snapped:       bool,
	non_snapped_size: [2]f32,
	fade:             f32,
	can_move:         bool,
	can_resize:       bool,
	dead:             bool,
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
	padding: f32 = 0,
	can_resize: bool = true,
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
		panel.can_resize = can_resize
	}

	push_stack(&global_state.panel_stack, panel)

	push_current_placement_options()

	if panel.moving == true {
		mouse_point := mouse_point()
		panel.moving = false
		size := panel.box.hi - panel.box.lo
		panel.box.lo = mouse_point - panel.move_offset
		panel.box.hi = panel.box.lo + size
		global_state.panel_snapping.active_panel = panel
		draw_frames(1)
	}

	min_size := linalg.max(MIN_SIZE, panel.min_size)
	if panel.resizing {
		panel.resizing = false
		panel.box.hi = global_state.mouse_pos + panel.resize_offset
	}
	// panel.box.lo = linalg.clamp(
	// 	panel.box.lo,
	// 	linalg.min(global_state.view - box_size(panel.box), 0),
	// 	linalg.max(global_state.view - box_size(panel.box), 0),
	// )
	if panel.can_resize {
		panel.box.hi = linalg.max(panel.box.hi, panel.box.lo + min_size)
	} else {
		panel.box.hi = panel.box.lo + min_size
	}
	panel.box = snapped_box(panel.box)

	if panel.last_min_size != panel.min_size {
		draw_frames(1)
	}
	panel.last_min_size = panel.min_size
	panel.min_size = {}

	begin_layer(kind = .Floating) or_return
	panel.layer = current_layer().?

	rounding := f32(0 if panel.is_snapped else global_state.style.rounding)

	{
		object := persistent_object(hash("panelbg"))
		object.placement = panel.box
		if begin_object(object) {
			defer end_object()

			if object.variant == nil {
				object.state.input_mask = OBJECT_STATE_ALL
			}

			handle_object_click(object, sticky = true)

			if point_in_box(global_state.mouse_pos, object.box) {
				hover_object(object)
			}

			if .Clicked in object.state.current && object.input.click_count == 2 {
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
				if vgo.disable_scissor() {
					vgo.box_shadow(
						move_box(panel.box, 3),
						global_state.style.rounding,
						6,
						vgo.fade(global_state.style.color.shadow, 1.0 - (0.1 * panel.fade)),
					)
				}
			}

			vgo.fill_box(panel.box, rounding, paint = global_state.style.color.fg)
		}
	}

	vgo.push_scissor(vgo.make_box(panel.box, rounding))
	push_clip(panel.box)
	begin_layout(placement = Box(panel.box), padding = padding) or_return
	return true
}

end_panel :: proc() {
	layout_object := current_object().?
	end_layout()
	pop_clip()

	panel := current_panel()
	if panel.can_resize {
		object := persistent_object(hash("resize"))
		object.placement = Box{panel.box.hi - global_state.style.visual_size.y * 0.5, panel.box.hi}
		if begin_object(object) {
			defer end_object()

			handle_object_click(object, sticky = true)
			if point_in_box(mouse_point(), object.box) {
				hover_object(object)
			}
			icon_color := global_state.style.color.substance
			if .Hovered in object.state.current {
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
			if .Pressed in object.state.current {
				panel.resizing = true
				if .Pressed not_in object.state.previous {
					panel.resize_offset = panel.box.hi - global_state.mouse_pos
				}
			}
		}
	}

	if panel.fade > 0 {
		vgo.fill_box(panel.box, 0, vgo.fade(vgo.BLACK, panel.fade * 0.05))
	}
	panel.fade = animate(
		panel.fade,
		0.25,
		panel.layer.index < global_state.last_highest_layer_index,
	)

	panel.min_size += layout_object.metrics.desired_size

	pop_id()
	vgo.pop_scissor()
	end_layer()
	pop_placement_options()
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

Panel_Snap_State :: struct {
	active_panel: Maybe(^Panel),
	snaps:        [8]Panel_Snap,
	snap_count:   int,
}

Panel_Snap :: enum {
	Top,
	Bottom,
	Left,
	Right,
	Center,
}

reset_panel_snap_state :: proc(state: ^Panel_Snap_State) {
	state.active_panel = nil
}

draw_panel_snap_widgets :: proc(state: Panel_Snap_State) {
	if panel, ok := state.active_panel.?; ok {
		OFFSET_FROM_EDGE :: 20
		RADIUS :: 35

		Snap_Orb :: struct {
			position: [2]f32,
			box:      Box,
		}

		screen_size := global_state.view

		orbs: [5]Snap_Orb = {
			{
				position = {OFFSET_FROM_EDGE + RADIUS, screen_size.y / 2},
				box = {{}, {screen_size.x / 2, screen_size.y}},
			},
			{
				position = {screen_size.x - (OFFSET_FROM_EDGE + RADIUS), screen_size.y / 2},
				box = {{screen_size.x / 2, 0}, screen_size},
			},
			{
				position = {screen_size.x / 2, OFFSET_FROM_EDGE + RADIUS},
				box = {{}, {screen_size.x, screen_size.y / 2}},
			},
			{
				position = {screen_size.x / 2, screen_size.y - (OFFSET_FROM_EDGE + RADIUS)},
				box = {{0, screen_size.y / 2}, screen_size},
			},
			{position = screen_size / 2, box = view_box()},
		}

		for orb in orbs {
			distance_to_mouse := linalg.length(mouse_point() - orb.position)
			if distance_to_mouse <= RADIUS {
				vgo.stroke_box(orb.box, 2, paint = colors().accent)
				if mouse_released(.Left) {
					panel.box = orb.box
					panel.is_snapped = true
				}
			} else {
				vgo.fill_circle(orb.position, RADIUS, vgo.fade(colors().accent, 0.5))
			}
		}
	}
}
