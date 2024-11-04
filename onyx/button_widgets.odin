package onyx

import "../../vgo"
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
	using _:       Widget_Info,
	text:          string,
	is_loading:    bool,
	style:         Button_Style,
	font:          Maybe(int),
	font_size:     Maybe(f32),
	color:         Maybe(vgo.Color),
	sharp_corners: [4]bool,
	text_layout:   vgo.Text_Layout,
	clicked:       bool,
}

make_button :: proc(info: Button_Info, loc := #caller_location) -> Button_Info {
	info := info
	init_button(&info, loc)
	return info
}

init_button :: proc(using info: ^Button_Info, loc := #caller_location) -> bool {
	if info == nil do return false
	text_layout = vgo.make_text_layout(
		text,
		core.style.default_font,
		font_size.? or_else core.style.default_text_size,
	)
	desired_size = text_layout.size + core.style.text_padding * 2
	if id == 0 do id = hash(loc)
	self = get_widget(id) or_return
	return true
}

add_button :: proc(using info: ^Button_Info) -> bool {
	begin_widget(info) or_return
	defer end_widget()

	button_behavior(self)

	if self.visible {
		text_color: vgo.Color
		radius: [4]f32 =
			(1.0 - linalg.array_cast(linalg.array_cast(info.sharp_corners, i32), f32)) *
			core.style.rounding

		switch style {
		case .Outlined:
			vgo.fill_box(
				self.box,
				radius,
				vgo.fade(color.? or_else core.style.color.substance, self.hover_time * 0.2),
			)
			vgo.stroke_box(self.box, 1, radius, color.? or_else core.style.color.substance)
			text_color = core.style.color.content

		case .Secondary:
			vgo.fill_box(
				self.box,
				radius,
				vgo.mix(self.hover_time * 0.2, color.? or_else core.style.color.substance, vgo.BLACK),
			)
			text_color = core.style.color.content

		case .Primary:
			vgo.fill_box(
				self.box,
				radius,
				vgo.mix(self.hover_time * 0.2, core.style.color.accent, vgo.BLACK),
			)
			text_color = core.style.color.content

		case .Ghost:
			vgo.fill_box(
				self.box,
				radius,
				paint = vgo.fade(
					color.? or_else core.style.color.substance,
					self.hover_time * 0.5,
				),
			)
			text_color = core.style.color.content
		}

		if self.press_time > 0 {
			scale := self.press_time if .Pressed in self.state else f32(1)
			opacity := f32(1) if .Pressed in self.state else self.press_time
			vgo.fill_box(
				self.box,
				radius,
				vgo.make_radial_gradient(
					self.click_point,
					max(box_width(self.box), box_height(self.box)) * scale,
					vgo.fade(vgo.WHITE, opacity * 0.333),
					vgo.fade(vgo.WHITE, 0),
				),
			)
		}
		if !is_loading {
			vgo.fill_text_layout_aligned(
				text_layout,
				box_center(self.box),
				.Center,
				.Center,
				text_color,
			)
		}

		if self.disable_time > 0 {
			vgo.fill_box(self.box, paint = vgo.fade(core.style.color.fg, self.disable_time * 0.5))
		}

		if is_loading {
			vgo.spinner(box_center(self.box), box_height(self.box) * 0.3, text_color)
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
				// center := box_center(self.box)
				// set_paint(add_paint({kind = .Atlas_Sample}))
				// defer set_paint(0)
				// shape := add_shape_box(
				// 	{center - image_size / 2, center + image_size / 2},
				// 	core.style.rounding,
				// )
				// h_overlap := max(0, image_size.x - view_size.x)
				// source.lo.x += h_overlap / 2
				// source.hi.x -= h_overlap / 2
				// v_overlap := max(0, image_size.y - view_size.y)
				// source.lo.y += v_overlap / 2
				// source.hi.y -= v_overlap / 2
				// render_shape_uv(shape, source, 255)
			}
		} else {
			vgo.fill_box(self.box, paint = vgo.Paint{kind = .Skeleton})
		}
		vgo.fill_box(
			self.box,
			core.style.rounding,
			paint = vgo.fade(core.style.color.substance, self.hover_time * 0.5),
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
	text_layout = vgo.make_text_layout(
		text,
		core.style.default_font,
		font_size.? or_else core.style.default_text_size,
	)
	desired_size = text_layout.size + 20
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
		vgo.fill_box(
			self.box,
			rounding,
			vgo.fade(
				vgo.mix(self.hover_time, core.style.color.field, core.style.color.accent),
				math.lerp(f32(0.75), f32(1.0), self.hover_time),
			),
		)
		vgo.fill_text_layout(text_layout, box_center(self.box), core.style.color.content)
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
