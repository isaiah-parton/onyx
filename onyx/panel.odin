package onyx

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
	min_size:             [2]f32,
	moving:               bool,
	resizing:             bool,
	dismissed:            bool,
	resize_offset:        [2]f32,
	can_move, can_resize: bool,
	dead:                 bool,
}

create_panel :: proc(id: Id) -> Maybe(^Panel) {
	for i in 0 ..< len(core.panels) {
		if core.panels[i] == nil {
			core.panels[i] = Panel{}
			core.panel_map[id] = &core.panels[i].?
			return &core.panels[i].?
		}
	}
	return nil
}

begin_panel :: proc(info: Panel_Info, loc := #caller_location) -> bool {

	MIN_SIZE :: [2]f32{100, 100}

	id := hash(loc)
	panel, ok := core.panel_map[id]
	if !ok {
		panel = create_panel(id).? or_return

		position := info.position.? or_else get_next_panel_position()
		size := info.size.? or_else MIN_SIZE
		panel.box = {position, position + size}

		panel.can_move = true
		panel.can_resize = true
	}

	// Push to stack
	push_stack(&core.panel_stack, panel)

	push_id(id)
	defer pop_id()

	if panel.moving == true {
		if mouse_released(.Left) {
			panel.moving = false
		}
		size := panel.box.hi - panel.box.lo
		panel.box.lo = core.mouse_pos - panel.move_offset
		panel.box.hi = panel.box.lo + size

		core.draw_next_frame = true
	}

	// Resizing
	if panel.resizing {
		if mouse_released(.Left) {
			panel.resizing = false
		}
		min_size := linalg.max(MIN_SIZE, panel.min_size)
		panel.box.hi = core.mouse_pos + panel.resize_offset
	}
	panel.box.hi = linalg.max(panel.box.hi, panel.box.lo + panel.min_size)

	panel.box = {linalg.floor(panel.box.lo), linalg.floor(panel.box.hi)}

	// Reset min_size to be calculated again
	panel.min_size = {}

	// Begin the panel layer
	begin_layer({id = id, box = expand_box(panel.box, 10)})
	panel.layer = current_layer().?

	// Background
	draw_rounded_box_fill(move_box(panel.box, 5), core.style.rounding, {0, 0, 0, 70})
	draw_rounded_box_fill(panel.box, core.style.rounding, core.style.color.foreground)

	// The content layout box
	inner_box := panel.box

	TITLE_HEIGHT :: 28
	if info.title != "" {
		panel.min_size.y += TITLE_HEIGHT
		title_box := cut_box_top(&inner_box, TITLE_HEIGHT)

		draw_rounded_box_corners_fill(
			title_box,
			core.style.rounding,
			{.Top_Left, .Top_Right},
			fade(core.style.color.substance, 0.5),
		)

		draw_text(
			{title_box.lo.x + 5, (title_box.hi.y + title_box.lo.y) / 2},
			{text = info.title, font = core.style.fonts[.Regular], size = 20, align_v = .Middle},
			core.style.color.content,
		)

		dismiss_button := Widget_Info {
			id  = hash("dismiss"),
			box = cut_box_right(&title_box, box_height(title_box)),
		}
		if begin_widget(&dismiss_button) {
			defer end_widget()

			self := dismiss_button.self

			button_behavior(self)

			draw_rounded_box_corners_fill(
				self.box,
				core.style.rounding,
				{.Top_Right},
				fade({200, 50, 50, 255}, self.hover_time),
			)

			// Resize icon
			origin := box_center(self.box)
			scale := box_height(self.box) * 0.2
			icon_color := alpha_blend_colors(
				core.style.color.foreground,
				core.style.color.content,
				0.5 + 0.5 * self.hover_time,
			)
			draw_line(origin - scale, origin + scale, 2, icon_color)
			draw_line(origin + {-scale, scale}, origin + {scale, -scale}, 2, icon_color)

			if .Pressed in (self.state - self.last_state) {
				panel.dismissed = true
			}
		}
	}

	// Resizing
	if panel.can_resize {
		resize_button := Widget_Info {
			id  = hash("resize"),
			box = Box{panel.box.hi - core.style.visual_size.y, panel.box.hi},
		}
		if begin_widget(&resize_button) {
			defer end_widget()

			self := resize_button.self

			button_behavior(self)

			draw_rounded_box_corners_fill(
				self.box,
				core.style.rounding,
				{.Bottom_Right},
				fade(core.style.color.substance, 0.5 * self.hover_time),
			)

			// Resize icon
			origin := box_center(self.box)
			scale := box_height(self.box) * 0.2
			icon_color := alpha_blend_colors(
				core.style.color.foreground,
				core.style.color.content,
				0.5 + 0.5 * self.hover_time,
			)
			begin_path()
			point(origin + {-0.3, -1} * scale)
			point(origin + {-1, -1} * scale)
			point(origin + {-1, -0.3} * scale)
			stroke_path(2, icon_color)
			end_path()
			begin_path()
			point(origin + {0.3, 1} * scale)
			point(origin + {1, 1} * scale)
			point(origin + {1, 0.3} * scale)
			stroke_path(2, icon_color)
			end_path()
			draw_line(origin - scale, origin + scale, 2, icon_color)

			if .Pressed in (self.state - self.last_state) {
				panel.resizing = true
				panel.resize_offset = panel.box.hi - core.mouse_pos
			}
		}
		// PADDING := core.style.rounding
		// OUTER :: 10
		// INNER :: 2
		// hover_boxes: [Side]Box = {
		// 	.Left   = Box {
		// 		{panel.box.lo.x - OUTER, panel.box.lo.y + PADDING},
		// 		{panel.box.lo.x + INNER, panel.box.hi.y - PADDING},
		// 	},
		// 	.Right  = Box {
		// 		{panel.box.hi.x - INNER, panel.box.lo.y + PADDING},
		// 		{panel.box.hi.x + OUTER, panel.box.hi.y - PADDING},
		// 	},
		// 	.Top    = Box {
		// 		{panel.box.lo.x + PADDING, panel.box.lo.y - OUTER},
		// 		{panel.box.hi.x - PADDING, panel.box.lo.y + INNER},
		// 	},
		// 	.Bottom = Box {
		// 		{panel.box.lo.x + PADDING, panel.box.hi.y - INNER},
		// 		{panel.box.hi.x - PADDING, panel.box.hi.y + OUTER},
		// 	},
		// }
		// DRAW_THICKNESS :: 1
		// draw_boxes: [Side]Box = {
		// 	.Left   = Box {
		// 		{panel.box.lo.x, panel.box.lo.y + PADDING},
		// 		{panel.box.lo.x + DRAW_THICKNESS, panel.box.hi.y - PADDING},
		// 	},
		// 	.Right  = Box {
		// 		{panel.box.hi.x - DRAW_THICKNESS, panel.box.lo.y + PADDING},
		// 		{panel.box.hi.x, panel.box.hi.y - PADDING},
		// 	},
		// 	.Top    = Box {
		// 		{panel.box.lo.x + PADDING, panel.box.lo.y},
		// 		{panel.box.hi.x - PADDING, panel.box.lo.y + DRAW_THICKNESS},
		// 	},
		// 	.Bottom = Box {
		// 		{panel.box.lo.x + PADDING, panel.box.hi.y - DRAW_THICKNESS},
		// 		{panel.box.hi.x - PADDING, panel.box.hi.y},
		// 	},
		// }
		// push_id(panel.layer.id)
		// for side, s in Side {
		// 	widget, ok := begin_widget({id = hash(s)})
		// 	if !ok do continue

		// 	widget.draggable = true
		// 	widget.box = hover_boxes[side]

		// 	if point_in_box(core.mouse_pos, widget.box) {
		// 		hover_widget(widget)
		// 	}

		// 	widget.hover_time = animate(widget.hover_time, 0.2, .Hovered in widget.state)
		// 	draw_box_fill(draw_boxes[side], fade(core.style.color.content, widget.hover_time))

		// 	if .Pressed in widget.state {
		// 		panel.resize = side
		// 	}

		// 	if .Hovered in widget.state {
		// 		core.cursor_type = .Resize_NS if int(side) > 1 else .Resize_EW
		// 	}

		// 	end_widget()
		// }
		// pop_id()
	}

	// Title bar
	if info.title != "" {
		title_box := get_box_cut_top(panel.box, TITLE_HEIGHT)
		// Dragging
		if panel.can_move &&
		   panel.resizing == false &&
		   .Hovered in panel.layer.state &&
		   point_in_box(core.mouse_pos, title_box) {
			if mouse_pressed(.Left) {
				panel.moving = true
				panel.move_offset = core.mouse_pos - panel.box.lo
			}
		}
	}

	push_layout(Layout{box = inner_box, next_cut_side = .Top})

	return true
}

end_panel :: proc() {
	panel := current_panel()
	// Panel outline
	draw_rounded_box_stroke(panel.box, core.style.rounding, 1, core.style.color.substance)
	draw_rounded_box_stroke(
		expand_box(panel.box, 1),
		core.style.rounding * 1.25,
		1,
		core.style.color.background,
	)
	layout := current_layout().?
	panel.min_size += layout.content_size + layout.spacing_size
	pop_layout()
	end_layer()
	pop_stack(&core.panel_stack)
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
	assert(core.panel_stack.height > 0, "There is no current panel!", loc)
	return core.panel_stack.items[core.panel_stack.height - 1]
}

get_next_panel_position :: proc() -> [2]f32 {
	pos: [2]f32 = 100
	for i in 0 ..< len(core.panels) {
		if panel, ok := core.panels[i].?; ok {
			if pos == panel.box.lo {
				pos += 50
			}
		}
	}
	return pos
}
