package ui

import "core:math"
import "core:math/ease"
import "core:math/linalg"

Checkbox_Info :: struct {
	using generic: Generic_Widget_Info,
	value: bool,
	text: string,
	text_side: Maybe(Side),
}

checkbox :: proc(info: Checkbox_Info, loc := #caller_location) -> Generic_Widget_Result {
	SIZE :: 22
	HALF_SIZE :: SIZE / 2
	PADDING :: 4
	// Check if there is text
	has_text := len(info.text) > 0
	// Default orientation
	text_side := info.text_side.? or_else .Left
	// Determine total size
	size, text_size: [2]f32
	if has_text {
		text_size = measure_text({font = core.style.fonts[.Regular], size = 18, text = info.text})
		if text_side == .Bottom || text_side == .Top {
			size.x = max(SIZE, text_size.x)
			size.y = SIZE + text_size.y
		} else {
			size.x = SIZE + text_size.x + PADDING * 2
			size.y = SIZE
		}
	} else {
		size = SIZE
	}
	layout := current_layout()
	// Create
	self := get_widget(info, loc)
	// Colocate
	self.box = info.box.? or_else align_inner(next_widget_box(), size, {.Middle, .Middle})
	// Animate
	self.hover_time = animate(self.hover_time, 0.1, .Hovered in self.state)
	// Painting
	if self.visible {
		icon_box: Box
		if has_text {
			switch text_side {
				case .Left:
				icon_box = {self.box.low, SIZE}
				case .Right:
				icon_box = {{self.box.high.x - SIZE, self.box.low.y}, SIZE}
				case .Top:
				icon_box = {{center_x(self.box) - HALF_SIZE, self.box.high.y - SIZE}, SIZE}
				case .Bottom:
				icon_box = {{center_x(self.box) - HALF_SIZE, self.box.low.y}, SIZE}
			}
			icon_box.low = linalg.floor(icon_box.low)
			icon_box.high += icon_box.low
		} else {
			icon_box = self.box
		}
		// Paint box
		opacity: f32 = 0.5 if self.disabled else 1
		draw_rounded_box_stroke(icon_box, core.style.rounding, 1, core.style.color.substance)
		center := box_center(icon_box)
		// Hover 
		if self.hover_time > 0 {
			draw_rounded_box_fill(self.box, core.style.rounding, fade(core.style.color.substance, 0.5 * self.hover_time))
		}
		// Paint icon
		if info.value {
			scale: f32 = HALF_SIZE * 0.5
			begin_path()
			point(center + {-1, -0.047} * scale)
			point(center + {-0.333, 0.619} * scale)
			point(center + {1, -0.713} * scale)
			stroke_path(2, core.style.color.content)
			end_path()
		}
		// Paint text
		if has_text {
			switch text_side {
				case .Left: 	
				draw_text({icon_box.high.x + PADDING, center.y - text_size.y / 2}, {text = info.text, font = core.style.fonts[.Regular], size = 18}, fade(core.style.color.content, opacity))
				case .Right: 	
				draw_text({icon_box.low.x - PADDING, center.y - text_size.y / 2}, {text = info.text, font = core.style.fonts[.Regular], size = 18, align_h = .Right}, fade(core.style.color.content, opacity))
				case .Top: 		
				draw_text(self.box.low, {text = info.text, font = core.style.fonts[.Regular], size = 18}, fade(core.style.color.content, opacity))
				case .Bottom: 	
				draw_text({self.box.low.x, self.box.high.y - text_size.y}, {text = info.text, font = core.style.fonts[.Regular], size = 18}, fade(core.style.color.content, opacity))
			}
		}
	}
	//
	commit_widget(self, point_in_box(core.mouse_pos, self.box))
	// We're done here
	return Generic_Widget_Result{self = self},
}