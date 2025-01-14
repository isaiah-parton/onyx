package onyx

import "../vgo"
import "base:intrinsics"
import "core:container/small_array"
import "core:fmt"
import "core:math"
import "core:math/ease"
import "core:math/linalg"
import "core:time"

Wave_Effects :: small_array.Small_Array(4, Wave_Effect)

draw_and_update_wave_effects :: proc(object: ^Object, array: ^Wave_Effects) {
	if .Pressed in new_state(object.state) {
		small_array.append(array, Wave_Effect{point = mouse_point()})
	}

	for &wave, i in array.data[:array.len] {
		vgo.fill_circle(
			wave.point,
			linalg.length(object.box.hi - object.box.lo) * min(wave.time, 0.75) * 1.33,
			paint = vgo.fade(vgo.WHITE, (1 - max(0, wave.time - 0.75) * 4) * 0.2),
		)

		if !(wave.time >= 0.75 && .Pressed in object.state.current && i == array.len - 1) {
			wave.time += 2.5 * global_state.delta_time
		}
	}

	draw_frames((array.len & 1) + 1)

	for array.len > 0 && array.data[0].time > 1 {
		small_array.pop_front(array)
	}
}

Button_Accent :: enum {
	Normal,
	Outlined,
	Subtle,
}

Button :: struct {
	waves:      Wave_Effects,
	hover_time: f32,
	press_time: f32,
}

Button_Result :: struct {
	clicked: bool,
	hovered: bool,
}

button :: proc(
	text: string,
	accent: Button_Accent = .Normal,
	font_size: f32 = global_state.style.default_text_size,
	active: bool = false,
	is_loading: bool = false,
	text_align: f32 = 0,
	loc := #caller_location,
) -> (
	result: Button_Result,
) {
	object := persistent_object(hash(loc))

	if object.variant == nil {
		object.variant = Button{}
	}

	extras := &object.variant.(Button)

	text_layout := vgo.make_text_layout(text, font_size, global_state.style.default_font)

	object.size = text_layout.size + global_state.style.text_padding * 2

	if begin_object(object) {

		object.box = next_box(object.size)

		handle_object_click(object)

		extras.press_time = animate(extras.press_time, 0.2, active)

		extras.hover_time = animate(extras.hover_time, 0.1, .Hovered in object.state.current)

		if .Hovered in object.state.current {
			set_cursor(.Pointing_Hand)
		}

		if point_in_box(global_state.mouse_pos, object.box) {
			hover_object(object)
		}

		if object_is_visible(object) {
			base_color := global_state.style.color.substance
			base_color = vgo.blend(base_color, global_state.style.color.accent, extras.press_time)
			text_color: vgo.Color
			rounding := current_options().radius

			switch accent {
			case .Normal:
				vgo.fill_box(
					object.box,
					rounding,
					vgo.mix(0.2 * extras.hover_time, base_color, vgo.WHITE),
				)
				text_color = colors().accent_content
			case .Outlined:
				color := vgo.mix(0.2 * extras.hover_time, base_color, vgo.WHITE)
				vgo.stroke_box(object.box, 1, rounding, paint = color)
				vgo.fill_box(
					object.box,
					rounding,
					paint = vgo.fade(color, math.lerp(f32(0.25), f32(0.5), extras.press_time)),
				)
				text_color = colors().content
			case .Subtle:
				vgo.fill_box(
					object.box,
					rounding,
					paint = vgo.fade(base_color, (extras.hover_time + f32(i32(active))) * 0.25),
				)
				text_color = colors().content
			}

			vgo.push_scissor(vgo.make_box(object.box, rounding))
			draw_and_update_wave_effects(object, &extras.waves)
			vgo.pop_scissor()

			if is_loading {
				vgo.spinner(
					box_center(object.box),
					box_height(object.box) * 0.3,
					global_state.style.color.accent_content,
				)
			} else {
				vgo.fill_text_layout(
					text_layout,
					{
						math.lerp(
							object.box.lo.x + global_state.style.text_padding.x,
							object.box.hi.y - global_state.style.text_padding.x,
							text_align,
						),
						box_center_y(object.box),
					},
					align = {text_align, 0.5},
					paint = text_color,
				)
			}
		}

		result.clicked = object_was_clicked(object, with = .Left)
		result.hovered = .Hovered in object.state.previous

		end_object()
	}
	return
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
	object = get_object(id)
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
