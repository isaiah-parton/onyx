package onyx

import "core:math"
import "core:math/ease"
import "core:math/linalg"
import "core:time"

Button_Style :: enum {
	Normal,
	Outline,
	Glass,
}

Button_Info :: struct {
	using _:    Widget_Info,
	text:       string,
	is_loading: bool,
	style:      Button_Style,
	font:       Maybe(int),
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
	desired_size = text_job.size + core.style.text_padding * 2
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

		fill_color := lerp_colors(
			(self.hover_time + self.press_time) * 0.1,
			color.? or_else core.style.color.substance,
			255,
		)

		switch style {
		case .Normal:
			fill_box(
				self.box,
				core.style.rounding,
				fill_color,
			)
			text_color = core.style.color.content
		case .Outline:
			fill_box(
				self.box,
				core.style.rounding,
				fade(fill_color, 0.5),
			)
			draw_rounded_box_stroke(
				self.box,
				core.style.rounding,
				1,
				fill_color,
			)
				text_color = core.style.color.content
		case .Glass:
			greater := max(box_width(self.box), box_height(self.box))
			set_paint(
				add_radial_gradient(
					{box_center_x(self.box), self.box.lo.y},
					math.lerp(greater * 0.5, greater, (self.hover_time + self.press_time) * 0.5),
					255,
					{255, 255, 255, 100},
				),
			)
			fill_box(
				self.box,
				core.style.rounding,
				fade(fill_color, 0.5),
			)
			draw_rounded_box_stroke(self.box, core.style.rounding, 1, fill_color)
			set_paint(0)
			text_color = core.style.color.content
		}

		if !is_loading {
			draw_text_glyphs(text_job, box_center(self.box), text_color)
		}

		if self.disable_time > 0 {
			fill_box(
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

Image_Button_Info :: struct {
	using _: Widget_Info,
	image:   Maybe(int),
	clicked: bool,
	hovered: bool,
}

init_image_button :: proc(using info: ^Image_Button_Info, loc := #caller_location) -> bool {
	if info == nil do return false
	if id == 0 do id = hash(loc)
	self = get_widget(id) or_return
	return true
}

add_image_button :: proc(using info: ^Image_Button_Info) -> bool {
	begin_widget(info) or_return
	defer end_widget()

	button_behavior(self)

	if self.visible {
		if image, ok := image.?; ok {
			if source, ok := core.user_images[image].?; ok {
				view_size := box_size(self.box)
				image_size := box_size(source)
				j := 0 if image_size.x < image_size.y else 1
				for i in 0 ..= 1 {
					image_size *= min(1, view_size[j] / image_size[j])
					j = 1 - j
				}
				center := box_center(self.box)
				set_paint(add_paint({kind = .Atlas_Sample}))
				defer set_paint(0)
				shape := add_shape(make_box(
					{center - image_size / 2, center + image_size / 2},
					core.style.rounding,
				))
				h_overlap := max(0, image_size.x - view_size.x)
				source.lo.x += h_overlap / 2
				source.hi.x -= h_overlap / 2
				v_overlap := max(0, image_size.y - view_size.y)
				source.lo.y += v_overlap / 2
				source.hi.y -= v_overlap / 2
				draw_shape_uv(shape, source, 255)
			}
		} else {
			draw_skeleton(self.box, core.style.rounding)
		}
		fill_box(
			self.box,
			fade(core.style.color.substance, self.hover_time * 0.5),
			radius = core.style.rounding,
		)
		// draw_rounded_box_stroke(self.box, core.style.rounding, 1, core.style.color.substance)
	}

	clicked = .Clicked in self.state
	hovered = .Hovered in self.state

	return true
}

image_button :: proc(info: Image_Button_Info) -> Image_Button_Info {
	info := info
	if init_image_button(&info) {
		add_image_button(&info)
	}
	return info
}

Floating_Button_Info :: Button_Info

init_floating_button :: proc(using info: ^Floating_Button_Info, loc := #caller_location) -> bool {
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
	desired_size = text_job.size + 20
	desired_size.x = max(desired_size.x, desired_size.y)
	if id == 0 do id = hash(loc)
	self = get_widget(id) or_return
	return true
}

add_floating_button :: proc(using info: ^Floating_Button_Info) -> bool {
	begin_widget(info) or_return
	defer end_widget()

	button_behavior(self)

	if self.visible {
		rounding := math.lerp(box_height(self.box) / 2, core.style.rounding, self.hover_time)
		// draw_shadow(self.box, rounding)
		fill_box(
			self.box,
			fade(
				lerp_colors(self.hover_time, core.style.color.background, core.style.color.accent),
				math.lerp(f32(0.75), f32(1.0), self.hover_time),
			),
			radius = rounding,
		)
		draw_text_glyphs(text_job, box_center(self.box), core.style.color.content)
	}

	clicked = .Clicked in self.state

	return true
}

floating_button :: proc(
	info: Floating_Button_Info,
	loc := #caller_location,
) -> Floating_Button_Info {
	info := info
	if init_floating_button(&info, loc) {
		add_floating_button(&info)
	}
	return info
}
