package onyx

import "core:math"
import "core:math/ease"
import "core:math/linalg"
import "core:time"

Button_Kind :: enum {
	Primary,
	Secondary,
	Outlined,
	Ghost,
}

Button_Info :: struct {
	using _:    Generic_Widget_Info,
	text:       string,
	is_loading: bool,
	kind:       Button_Kind,
	font_style: Maybe(Font_Style),
	font_size:  Maybe(f32),
	color:      Maybe(Color),
	__text_job: Text_Job,
}

make_button :: proc(info: Button_Info, loc := #caller_location) -> Button_Info {
	info := info
	info.id = hash(loc)
	text_info := Text_Info {
		text    = info.text,
		size    = info.font_size.? or_else core.style.button_text_size,
		font    = core.style.fonts[info.font_style.? or_else .Medium],
		align_v = .Middle,
		align_h = .Middle,
	}
	info.__text_job, _ = make_text_job(text_info)
	info.desired_size = info.__text_job.size + {18, 6}
	return info
}

add_button :: proc(info: Button_Info) -> (result: Generic_Widget_Result) {
	widget, ok := begin_widget(info)
	if !ok do return

	result.self = widget

	button_behavior(widget)

	if widget.visible {
		text_color: Color

		switch info.kind {
		case .Outlined:
			draw_rounded_box_fill(
				widget.box,
				core.style.rounding,
				fade(info.color.? or_else core.style.color.substance, widget.hover_time),
			)
			if widget.hover_time < 1 {
				draw_rounded_box_stroke(
					widget.box,
					core.style.rounding,
					1,
					info.color.? or_else core.style.color.substance,
				)
			}
			text_color = core.style.color.content

		case .Secondary:
			draw_rounded_box_fill(
				widget.box,
				core.style.rounding,
				interpolate_colors(
					widget.hover_time * 0.25,
					info.color.? or_else core.style.color.substance,
					core.style.color.foreground,
				),
			)
			text_color = core.style.color.content

		case .Primary:
			draw_rounded_box_fill(
				widget.box,
				core.style.rounding,
				interpolate_colors(
					widget.hover_time * 0.25,
					info.color.? or_else core.style.color.accent,
					core.style.color.foreground,
				),
			)
			text_color = core.style.color.accent_content

		case .Ghost:
			draw_rounded_box_fill(
				widget.box,
				core.style.rounding,
				fade(info.color.? or_else core.style.color.substance, widget.hover_time),
			)
			text_color = core.style.color.content
		}

		if !info.is_loading {
			draw_text_glyphs(info.__text_job, box_center(widget.box), text_color)
		}

		if widget.disable_time > 0 {
			draw_rounded_box_fill(
				widget.box,
				core.style.rounding,
				fade(core.style.color.background, widget.disable_time * 0.5),
			)
		}

		if info.is_loading {
			draw_loader(box_center(widget.box), 10, text_color)
		}
	}

	end_widget()
	return result
}

button :: proc(info: Button_Info, loc := #caller_location) -> Generic_Widget_Result {
	return add_button(make_button(info, loc))
}
