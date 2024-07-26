package ui

import "core:math"
import "core:math/ease"
import "core:math/linalg"

Button_Kind :: enum {
	Primary,
	Secondary,
	Outlined,
	Ghost,
}

Button_Info :: struct {
	using _: Generic_Widget_Info,
	text: string,
	kind: Button_Kind,
}

Button_Result :: struct {
	using _: Generic_Widget_Result,
}

measure_button :: proc(desc: Button_Info) -> (width: f32) {
	return
}

button :: proc(info: Button_Info, loc := #caller_location) -> (res: Button_Result) {
	widget := get_widget(info, loc)
	text_info: Text_Info = {
		text = info.text,
		font = core.style.fonts[.Bold],
		size = 18,//core.style.button_text_size,
	}
	text_size := measure_text(text_info)
	size := text_size + {20, 10}

	layout := current_layout()
	widget.box = cut_box(&layout.box, layout.next_side, size.x if int(layout.next_side) > 1 else size.y)
	widget.box.low = linalg.floor(widget.box.low)
	widget.box.high = linalg.floor(widget.box.high)
	widget.hover_time = animate(widget.hover_time, 0.1, .Hovered in widget.state)

	switch info.kind {
		case .Outlined:
		draw_rounded_box_fill(widget.box, core.style.rounding, fade(core.style.color.substance, widget.hover_time))
		if widget.hover_time < 1 {
			draw_rounded_box_stroke(widget.box, core.style.rounding, 1, core.style.color.substance)
		}
		draw_text(center(widget.box) - text_size / 2, text_info, core.style.color.content)

		case .Secondary:
		draw_rounded_box_fill(widget.box, core.style.rounding, blend_colors(widget.hover_time * 0.25, core.style.color.substance, core.style.color.foreground))
		draw_text(center(widget.box) - text_size / 2, text_info, core.style.color.content)

		case .Primary:
		draw_rounded_box_fill(widget.box, core.style.rounding, blend_colors(widget.hover_time * 0.25, core.style.color.content, core.style.color.foreground))
		text_info.font = core.style.fonts[.Medium]
		draw_text(center(widget.box) - text_size / 2, text_info, core.style.color.foreground)

		case .Ghost:
		draw_rounded_box_fill(widget.box, core.style.rounding, fade(core.style.color.substance, widget.hover_time))
		draw_text(center(widget.box) - text_size / 2, text_info, core.style.color.content)
	}

	hovered := point_in_box(core.mouse_pos, widget.box)
	if hovered {
		core.cursor_type = .POINTING_HAND
	}
	commit_widget(widget, hovered)
	return
}