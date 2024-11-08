package onyx

import "../../vgo"
import "core:container/small_array"
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

Button :: struct {
	using base:  ^Widget,
	text:        string,
	is_loading:  bool,
	style:       Button_Style,
	font_index:  Maybe(int),
	font_size:   Maybe(f32),
	color:       Maybe(vgo.Color),
	text_layout: vgo.Text_Layout,
}

make_button_text_layout :: proc(text: string, font_size: Maybe(f32) = nil) -> vgo.Text_Layout {
	return vgo.make_text_layout(
		text,
		global_state.style.default_font,
		font_size.? or_else global_state.style.default_text_size,
	)
}

button :: proc(text: string, loc := #caller_location) {
	widget := get_widget(hash(loc))
	text_layout := make_button_text_layout(text)
	widget.desired_size = text_layout.size + global_state.style.text_padding * 2
	if widget.variant == nil {
		widget.variant = Button{
			base = widget,
		}
	}
	button := &widget.variant.(Button)
	button.text_layout = text_layout
	if begin_widget(widget) {
		defer end_widget()

		widget.box = next_widget_box(widget.desired_size)

		handle_widget_click(widget)

		button_behavior(widget)
		button := widget.variant.(Button)

		if widget.visible {
			text_color: vgo.Color
			radius: [4]f32 = global_state.style.rounding
			shape := vgo.make_box(widget.box, radius)

			switch button.style {
			case .Outlined:
				vgo.fill_box(
					widget.box,
					radius,
					vgo.fade(
						button.color.? or_else global_state.style.color.substance,
						0.5 if .Hovered in widget.state else 0.25,
					),
				)
				vgo.stroke_box(
					widget.box,
					2,
					radius,
					button.color.? or_else global_state.style.color.substance,
				)
				text_color = global_state.style.color.content
			case .Secondary:
				bg_color := button.color.? or_else global_state.style.color.substance
				vgo.fill_box(
					widget.box,
					radius,
					vgo.mix(0.15, bg_color, vgo.WHITE) if .Hovered in widget.state else bg_color,
				)
				text_color = global_state.style.color.accent_content
			case .Primary:
				vgo.fill_box(
					widget.box,
					radius,
					vgo.mix(0.15, global_state.style.color.accent, vgo.WHITE) if .Hovered in widget.state else global_state.style.color.accent,
				)
				text_color = global_state.style.color.accent_content
			case .Ghost:
				if .Hovered in widget.state {
					vgo.fill_box(
						widget.box,
						radius,
						paint = vgo.fade(button.color.? or_else global_state.style.color.substance, 0.2),
					)
				}
				text_color = global_state.style.color.content
			}

			if widget.press_time > 0 {
				scale := widget.press_time if .Pressed in widget.state else f32(1)
				opacity := f32(1) if .Pressed in widget.state else widget.press_time
				vgo.push_scissor(shape)
				vgo.fill_circle(
					widget.click_point,
					linalg.length(widget.box.hi - widget.box.lo) * scale,
					paint = vgo.fade(vgo.WHITE, opacity * 0.2),
				)
				vgo.pop_scissor()
			}
			if !button.is_loading {
				vgo.fill_text_layout_aligned(
					button.text_layout,
					box_center(widget.box),
					.Center,
					.Center,
					text_color,
				)
			}

			if widget.disable_time > 0 {
				vgo.fill_box(
					widget.box,
					paint = vgo.fade(global_state.style.color.fg, widget.disable_time * 0.5),
				)
			}

			if button.is_loading {
				vgo.spinner(box_center(widget.box), box_height(widget.box) * 0.3, text_color)
			}
		}
	}
}

/*
Image_Button :: struct {
	using _: Widget_Info,
	image:   Maybe(int),
	clicked: bool,
	hovered: bool,
}

init_image_button :: proc(using info: ^Image_Button, loc := #caller_location) -> bool {
	if info == nil do return false
	if id == 0 do id = hash(loc)
	self = get_widget(id)
	return true
}

add_image_button :: proc(using info: ^Image_Button) -> bool {
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

image_button :: proc(info: Image_Button) -> Image_Button {
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
	self.desired_size = text_layout.size + 20
	self.desired_size.x = max(self.desired_size.x, self.desired_size.y)
	if id == 0 do id = hash(loc)
	self = get_widget(id)
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
*/
