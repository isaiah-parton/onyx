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

	__text_size: [2]f32,
	__text_info: Text_Info,
}

Button_Result :: struct {
	using _: Generic_Widget_Result,
}

make_button :: proc(info: Button_Info, loc := #caller_location) -> Button_Info {
	info := info
	info.id = hash(loc)
	info.__text_info = {
		text = info.text,
		font = core.style.fonts[.Bold],
		size = core.style.button_text_size,
	}
	info.__text_size = measure_text(info.__text_info)
	info.desired_size = info.__text_size + {20, 10}
	return info
}

display_button :: proc(info: Button_Info) -> (res: Button_Result) {
	widget := get_widget(info)
	layout := current_layout()
	widget.box = next_widget_box(info)
	widget.hover_time = animate(widget.hover_time, 0.1, .Hovered in widget.state)

	text_info := info.__text_info
	switch info.kind {
		case .Outlined:
		draw_rounded_box_fill(widget.box, core.style.rounding, fade(core.style.color.substance, widget.hover_time))
		if widget.hover_time < 1 {
			draw_rounded_box_stroke(widget.box, core.style.rounding, 1, core.style.color.substance)
		}
		draw_text(center(widget.box) - info.__text_size / 2, text_info, core.style.color.content)

		case .Secondary:
		draw_rounded_box_fill(widget.box, core.style.rounding, blend_colors(widget.hover_time * 0.25, core.style.color.substance, core.style.color.foreground))
		draw_text(center(widget.box) - info.__text_size / 2, text_info, core.style.color.content)

		case .Primary:
		draw_rounded_box_fill(widget.box, core.style.rounding, blend_colors(widget.hover_time * 0.25, core.style.color.content, core.style.color.foreground))
		text_info.font = core.style.fonts[.Medium]
		draw_text(center(widget.box) - info.__text_size / 2, text_info, core.style.color.foreground)

		case .Ghost:
		draw_rounded_box_fill(widget.box, core.style.rounding, fade(core.style.color.substance, widget.hover_time))
		draw_text(center(widget.box) - info.__text_size / 2, text_info, core.style.color.content)
	}

	hovered := point_in_box(core.mouse_pos, widget.box)
	if hovered {
		core.cursor_type = .POINTING_HAND
	}
	commit_widget(widget, hovered)
	return
}

do_button :: proc(info: Button_Info, loc := #caller_location) -> Button_Result {
	return display_button(make_button(info, loc))
}