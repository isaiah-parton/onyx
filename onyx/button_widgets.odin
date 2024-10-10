package onyx

import "core:math"
import "core:math/ease"
import "core:math/linalg"
import "core:time"

Button_Style :: enum {
	Primary,
	Secondary,
	Outlined,
	Ghost,
}

Button_Info :: struct {
	using _:    Widget_Info,
	text:       string,
	is_loading: bool,
	style:      Button_Style,
	font: Maybe(int),
	font_size:  Maybe(f32),
	color:      Maybe(Color),
	text_job:   Text_Job,
	clicked:    bool,
}

init_button :: proc(using info: ^Button_Info, loc := #caller_location) -> bool {
	if info == nil do return false
	text_job = make_text_job(
		{
			text = text,
			size = font_size.? or_else core.style.button_text_size,
			font = core.style.default_font,
			align_v = .Middle,
			align_h = .Middle,
		},
	) or_return
	desired_size = text_job.size + {18, 6}
	if id == 0 do id = hash(loc)
	self = get_widget(id) or_return
	return true
}

add_button :: proc(using info: ^Button_Info) -> bool {
	begin_widget(info) or_return
	defer end_widget()

	button_behavior(self)

	if self.visible {
		text_color: Color

		switch style {
		case .Outlined:
			draw_rounded_box_fill(
				self.box,
				core.style.rounding,
				fade(color.? or_else core.style.color.substance, self.hover_time * 0.5),
			)
			draw_rounded_box_stroke(
				self.box,
				core.style.rounding,
				1,
				color.? or_else core.style.color.substance,
			)
			text_color = core.style.color.content

		case .Secondary:
			draw_rounded_box_fill(
				self.box,
				core.style.rounding,
				lerp_colors(
					self.hover_time * 0.25,
					color.? or_else core.style.color.substance,
					core.style.color.foreground,
				),
			)
			text_color = core.style.color.content

		case .Primary:
			if self.hover_time > 0 {
				draw_rounded_box_shadow(
					self.box,
					core.style.rounding,
					6,
					fade({0, 0, 0, 40}, self.hover_time),
				)
			}
			draw_rounded_box_fill(
				self.box,
				core.style.rounding,
				lerp_colors(
					self.hover_time * 0.25,
					color.? or_else core.style.color.accent,
					core.style.color.foreground,
				),
			)
			text_color = core.style.color.accent_content

		case .Ghost:
			draw_rounded_box_fill(
				self.box,
				core.style.rounding,
				fade(color.? or_else core.style.color.substance, self.hover_time * 0.5),
			)
			text_color = core.style.color.content
		}

		if !is_loading {
			draw_text_glyphs(text_job, box_center(self.box), text_color)
		}

		if self.disable_time > 0 {
			draw_rounded_box_fill(
				self.box,
				core.style.rounding,
				fade(core.style.color.background, self.disable_time * 0.5),
			)
		}

		if is_loading {
			draw_spinner(box_center(self.box), box_height(self.box) * 0.3, text_color)
		}
	}

	clicked = .Clicked in self.state

	return true
}

button :: proc(info: Button_Info, loc := #caller_location) -> Button_Info {
	info := info
	if init_button(&info, loc) {
		add_button(&info)
	}
	return info
}
