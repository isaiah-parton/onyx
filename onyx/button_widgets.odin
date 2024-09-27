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
// Everything needed to construct a new button
Button_Info :: struct {
	// `Widget_Info.self` points to the internal generic `Widget`
	using _:    Widget_Info,
	text:       string,
	is_loading: bool,
	style:      Button_Style,
	font_style: Maybe(Font_Style),
	font_size:  Maybe(f32),
	color:      Maybe(Color),
}
// A constructed button with it's relevant retained data
Button :: struct {
	// Still contains a pointer to the internal generic `Widget`
	using info: Button_Info,
	hover_time: f32,
	text_job: 	Text_Job,
}
// r e s u l t
Button_Result :: struct {
	clicked: bool,
}

// Prepare a widget
make_button :: proc(info: Button_Info, loc := #caller_location) -> (button: Button, ok: bool) {
	button.info = info
	button.text_job = make_text_job({
		text    = button.text,
		size    = button.font_size.? or_else core.style.button_text_size,
		font    = core.style.fonts[button.font_style.? or_else .Medium],
		align_v = .Middle,
		align_h = .Middle,
	}) or_return
	button.desired_size = button.text_job.size + {18, 6}
	button.self = make_widget(button.id.? or_else hash(loc)) or_return
	return
}

// Now 'add' the button (display and get interaction)
add_button :: proc(using button: Button) {
	self.button = button
	begin_widget(button)

	button_behavior(self)

	if self.visible {
		text_color: Color

		switch button.style {
		case .Outlined:
			draw_rounded_box_fill(
				self.box,
				core.style.rounding,
				fade(button.color.? or_else core.style.color.substance, button.self.hover_time),
			)
			if button.hover_time < 1 {
				draw_rounded_box_stroke(
					self.box,
					core.style.rounding,
					1,
					button.color.? or_else core.style.color.substance,
				)
			}
			text_color = core.style.color.content

		case .Secondary:
			draw_rounded_box_fill(
				button.self.box,
				core.style.rounding,
				interpolate_colors(
					button.self.hover_time * 0.25,
					button.color.? or_else core.style.color.substance,
					core.style.color.foreground,
				),
			)
			text_color = core.style.color.content

		case .Primary:
			draw_rounded_box_fill(
				button.self.box,
				core.style.rounding,
				interpolate_colors(
					button.hover_time * 0.25,
					button.color.? or_else core.style.color.accent,
					core.style.color.foreground,
				),
			)
			text_color = core.style.color.accent_content

		case .Ghost:
			draw_rounded_box_fill(
				button.self.box,
				core.style.rounding,
				fade(button.color.? or_else core.style.color.substance, button.hover_time),
			)
			text_color = core.style.color.content
		}

		if !button.is_loading {
			draw_text_glyphs(button.__text_job, box_center(button.self.box), text_color)
		}

		// if button.self.disable_time > 0 {
		// 	draw_rounded_box_fill(
		// 		button.self.box,
		// 		core.style.rounding,
		// 		fade(core.style.color.background, button.self.disable_time * 0.5),
		// 	)
		// }

		if button.is_loading {
			draw_loader(box_center(button.self.box), 10, text_color)
		}
	}

	end_widget()
	return result
}

button :: proc(info: Button_Info, loc := #caller_location) -> Button_Result {
	return add_button(make_button(info, loc))
}
