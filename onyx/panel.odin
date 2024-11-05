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
	last_min_size:             [2]f32,
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

	if panel.moving == true {
		if mouse_released(.Left) {
			panel.moving = false
		}
		size := panel.box.hi - panel.box.lo
		panel.box.lo = core.mouse_pos - panel.move_offset
		panel.box.hi = panel.box.lo + size

		core.draw_next_frame = true
	}

	// Handle panel transforms
	min_size := linalg.max(MIN_SIZE, panel.min_size)
	if panel.resizing {
		if mouse_released(.Left) {
			panel.resizing = false
		}
		panel.box.hi = core.mouse_pos + panel.resize_offset
	}
	panel.box.hi = linalg.max(panel.box.hi, panel.box.lo + min_size)
	panel.box = snapped_box(panel.box)

	// Reset min_size to be calculated again
	if panel.last_min_size != panel.min_size {
		core.draw_this_frame = true
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

	vgo.push_scissor(vgo.make_box(panel.box, core.style.rounding))

	// Background
	background_widget := Widget_Info {
		id     = panel.layer.id,
		box    = panel.box,
		sticky = true,
		in_state_mask = WIDGET_STATE_ALL,
	}
	if begin_widget(&background_widget) {
		defer end_widget()
		using background_widget

		draw_shadow(self.box)
		vgo.fill_box(self.box, paint = core.style.color.fg)

		if point_in_box(core.mouse_pos, self.box) {
			hover_widget(self)
		}

		if .Pressed in self.state {
			panel.moving = true
			panel.move_offset = core.mouse_pos - panel.box.lo
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
			{core.style.rounding, core.style.rounding, 0, 0},
			vgo.fade(core.style.color.substance, 0.5),
		)

		vgo.fill_text_aligned(
			info.title,
			core.style.default_font,
			20,
			{title_box.lo.x + 5, (title_box.hi.y + title_box.lo.y) / 2},
			.Left,
			.Center,
			paint = core.style.color.content,
		)

		dismiss_button := Widget_Info {
			id  = hash("dismiss"),
			box = cut_box_right(&title_box, box_height(title_box)),
		}
		if begin_widget(&dismiss_button) {
			defer end_widget()

			self := dismiss_button.self

			button_behavior(self)

			vgo.fill_box(
				self.box,
				{1 = core.style.rounding},
				vgo.fade({200, 50, 50, 255}, self.hover_time),
			)

			// Resize icon
			origin := box_center(self.box)
			scale := box_height(self.box) * 0.2
			icon_color := vgo.blend(
				core.style.color.fg,
				core.style.color.content,
				0.5 + 0.5 * self.hover_time,
			)
			vgo.line(origin - scale, origin + scale, 2, icon_color)
			vgo.line(origin + {-scale, scale}, origin + {scale, -scale}, 2, icon_color)

			if .Pressed in (self.state - self.last_state) {
				panel.dismissed = true
			}
		}
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
		resize_button := Widget_Info {
			id  = hash("resize"),
			box = Box{panel.box.hi - core.style.visual_size.y * 0.75, panel.box.hi},
			sticky = true
		}
		if begin_widget(&resize_button) {
			defer end_widget()

			self := resize_button.self

			button_behavior(self)
			if .Hovered in self.state {
				core.cursor_type = .Resize_NWSE
			}

			// Resize icon
			icon_color := vgo.blend(
				core.style.color.substance,
				core.style.color.content,
				0.5 * self.hover_time,
			)
			vgo.fill_polygon(
				{
					{self.box.hi.x, self.box.lo.y},
					self.box.hi,
					{self.box.lo.x, self.box.hi.y}
				},
				paint = icon_color,
			)

			if .Pressed in (self.state - self.last_state) {
				panel.resizing = true
				panel.resize_offset = panel.box.hi - core.mouse_pos
			}
		}
	}

	if panel.fade > 0 {
		vgo.fill_box(panel.layer.box, 0, vgo.fade(vgo.BLACK, panel.fade * 0.15))
	}
	// panel.fade = animate(panel.fade, 0.15, panel.layer.index < core.last_highest_layer_index)

	// Panel outline
	// draw_rounded_box_stroke(panel.box, core.style.rounding, 1, core.style.color.substance)
	layout := current_layout().?
	panel.min_size += layout.content_size + layout.spacing_size
	pop_layout()
	pop_id()
	vgo.pop_scissor()
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
