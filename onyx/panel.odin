package onyx

import "../../vgo"
import "core:fmt"
import "core:math"
import "core:math/linalg"

Panel_Info :: struct {
	title:          string,
	position, size: Maybe([2]f32),
}

Panel :: struct {
	layer:                ^Layer,
	box:                  Box,
	move_offset:          [2]f32,
	last_min_size:        [2]f32,
	min_size:             [2]f32,
	moving:               bool,
	resizing:             bool,
	dismissed:            bool,
	resize_offset:        [2]f32,
	fade:                 f32,
	can_move, can_resize: bool,
	dead:                 bool,
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
		widget := get_widget(panel.layer.id)
		if begin_widget(widget) {
			defer end_widget()

			if widget.variant == nil {
				widget.in_state_mask = WIDGET_STATE_ALL
			}
			widget.box = panel.box

			handle_widget_click(widget, sticky = true)

			draw_shadow(widget.box)
			vgo.fill_box(widget.box, paint = global_state.style.color.fg)

			if point_in_box(global_state.mouse_pos, widget.box) {
				hover_widget(widget)
			}

			if .Pressed in widget.state {
				panel.moving = true
				panel.move_offset = global_state.mouse_pos - panel.box.lo
			}
		}
	}

	// The content layout box
	inner_box := panel.box

	TITLE_HEIGHT :: 28
	if len(info.title) > 0 {
		panel.min_size.y += TITLE_HEIGHT
		title_box := cut_box_top(&inner_box, TITLE_HEIGHT)

		vgo.fill_box(
			title_box,
			{global_state.style.rounding, global_state.style.rounding, 0, 0},
			vgo.fade(global_state.style.color.substance, 0.5),
		)

		vgo.fill_text_aligned(
			info.title,
			global_state.style.default_font,
			20,
			{title_box.lo.x + 5, (title_box.hi.y + title_box.lo.y) / 2},
			.Left,
			.Center,
			paint = global_state.style.color.content,
		)

		{
			widget := get_widget(hash("dismiss"))
			if begin_widget(widget) {
				defer end_widget()

				widget.box = cut_box_right(&title_box, box_height(title_box))
				button_behavior(widget)
				vgo.fill_box(
					widget.box,
					{1 = global_state.style.rounding},
					vgo.fade({200, 50, 50, 255}, widget.hover_time),
				)
				origin := box_center(widget.box)
				scale := box_height(widget.box) * 0.2
				icon_color := vgo.blend(
					global_state.style.color.fg,
					global_state.style.color.content,
					0.5 + 0.5 * widget.hover_time,
				)
				vgo.line(origin - scale, origin + scale, 2, icon_color)
				vgo.line(origin + {-scale, scale}, origin + {scale, -scale}, 2, icon_color)
				if .Pressed in (widget.state - widget.last_state) {
					panel.dismissed = true
				}
			}
		}
	}

	push_layout(Layout{box = inner_box, next_cut_side = .Top})

	return true
}

end_panel :: proc() {

	panel := current_panel()
	// Resizing
	if panel.can_resize {
		widget := get_widget(hash("resize"))
		if begin_widget(widget) {
			defer end_widget()
			widget.box = Box{panel.box.hi - global_state.style.visual_size.y * 0.5, panel.box.hi}
			handle_widget_click(widget, sticky = true)
			button_behavior(widget)
			if .Hovered in widget.state {
				global_state.cursor_type = .Resize_NWSE
			}
			icon_color := vgo.blend(
				global_state.style.color.substance,
				global_state.style.color.content,
				0.5 * widget.hover_time,
			)
			vgo.fill_polygon(
				{
					{widget.box.hi.x, widget.box.lo.y},
					widget.box.hi,
					{widget.box.lo.x, widget.box.hi.y},
				},
				paint = icon_color,
			)
			if .Pressed in widget.state {
				panel.resizing = true
				if .Pressed not_in widget.last_state {
					panel.resize_offset = panel.box.hi - global_state.mouse_pos
				}
			}
		}
	}

	if panel.fade > 0 {
		vgo.fill_box(panel.layer.box, 0, vgo.fade(vgo.BLACK, panel.fade * 0.15))
	}
	panel.fade = animate(panel.fade, 0.15, panel.layer.index < global_state.last_highest_layer_index)

	// Panel outline
	// draw_rounded_box_stroke(panel.box, core.style.rounding, 1, core.style.color.substance)
	layout := current_layout().?
	panel.min_size += layout.content_size + layout.spacing_size
	pop_layout()
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
