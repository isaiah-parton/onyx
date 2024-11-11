package onyx

import "../vgo"
import "core:container/small_array"
import "core:fmt"
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
	using object: ^Object,
	text:         string,
	is_loading:   bool,
	press_time:   f32,
	style:        Button_Style,
	font_index:   Maybe(int),
	font_size:    Maybe(f32),
	color:        Maybe(vgo.Color),
	text_layout:  vgo.Text_Layout,
}

button :: proc(text: string, style: Button_Style = .Primary, font_size: f32 = global_state.style.default_text_size, loc := #caller_location) {
	object := persistent_object(hash(loc))
	if begin_object(object) {
		defer end_object()

		if object.variant == nil {
			object.variant = Button {
				object = object,
			}
		}
		button := &object.variant.(Button)
		button.margin = 4
		button.text_layout = vgo.make_text_layout(
			text,
			global_state.style.default_font,
			font_size,
		)
		button.desired_size = button.text_layout.size + global_state.style.text_padding * 2
		button.style = style
	}
}

display_button :: proc(button: ^Button) {
	handle_object_click(button)
	button_behavior(button)
	if object_is_visible(button) {
		text_color: vgo.Color
		radius: [4]f32 = global_state.style.rounding

		switch button.style {
		case .Outlined:
			vgo.fill_box(
				button.box,
				radius,
				vgo.fade(
					button.color.? or_else global_state.style.color.substance,
					0.5 if .Hovered in button.state else 0.25,
				),
			)
			vgo.stroke_box(
				button.box,
				2,
				radius,
				button.color.? or_else global_state.style.color.substance,
			)
			text_color = global_state.style.color.content
		case .Secondary:
			bg_color := button.color.? or_else global_state.style.color.substance
			vgo.fill_box(
				button.box,
				radius,
				vgo.mix(0.15, bg_color, vgo.WHITE) if .Hovered in button.state else bg_color,
			)
			text_color = global_state.style.color.accent_content
		case .Primary:
			vgo.fill_box(
				button.box,
				radius,
				vgo.mix(0.15, global_state.style.color.accent, vgo.WHITE) if .Hovered in button.state else global_state.style.color.accent,
			)
			text_color = global_state.style.color.accent_content
		case .Ghost:
			if .Hovered in button.state {
				vgo.fill_box(
					button.box,
					radius,
					paint = vgo.fade(
						button.color.? or_else global_state.style.color.substance,
						0.2,
					),
				)
			}
			text_color = global_state.style.color.content
		}

		if button.press_time > 0 {
			scale := button.press_time if .Pressed in button.state else f32(1)
			opacity := f32(1) if .Pressed in button.state else button.press_time
			vgo.push_scissor(vgo.make_box(button.box, radius))
			vgo.fill_circle(
				button.click_point,
				linalg.length(button.box.hi - button.box.lo) * scale,
				paint = vgo.fade(vgo.WHITE, opacity * 0.2),
			)
			vgo.pop_scissor()
		}

		if !button.is_loading {
			vgo.fill_text_layout_aligned(
				button.text_layout,
				box_center(button.box),
				.Center,
				.Center,
				text_color,
			)
		}

		if button.is_loading {
			vgo.spinner(box_center(button.box), box_height(button.box) * 0.3, text_color)
		}
	}
}

/*
Image_Button :: struct {
	using _: Object_Info,
	image:   Maybe(int),
	clicked: bool,
	hovered: bool,
}

init_image_button :: proc(using info: ^Image_Button, loc := #caller_location) -> bool {
	if info == nil do return false
	if id == 0 do id = hash(loc)
	self = get_object(id)
	return true
}

add_image_button :: proc(using info: ^Image_Button) -> bool {
	begin_object(info) or_return
	defer end_object()

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
	self = get_object(id)
	return true
}

add_floating_button :: proc(using info: ^Floating_Button_Info) -> bool {
	begin_object(info) or_return
	defer end_object()

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
