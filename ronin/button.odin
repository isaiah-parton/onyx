package ronin

import kn "local:katana"
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
		kn.add_circle(
			wave.point,
			linalg.length(object.box.hi - object.box.lo) * min(wave.time, 0.75) * 1.33,
			paint = kn.fade(kn.White, (1 - max(0, wave.time - 0.75) * 4) * 0.2),
		)

		if !(wave.time >= 0.75 && .Pressed in object.state.current && i == array.len - 1) {
			wave.time += 2.5 * global_state.delta_time
		}
	}

	draw_frames(min(array.len, 1) * 2)

	for array.len > 0 && array.data[0].time > 1 {
		small_array.pop_front(array)
	}
}

Button_Accent :: enum {
	Normal,
	Primary,
	Subtle,
}

Button :: struct {
	hover_time:  f32,
	press_time:  f32,
	hold_time:   f32,
	active_time: f32,
}

Button_Result :: struct {
	click_count: int,
	clicked: bool,
	hovered: bool,
	pressed: bool,
}

button :: proc(
	label: string,
	accent: Button_Accent = .Normal,
	font_size: f32 = global_state.style.default_text_size,
	delay: f32 = 0,
	active: bool = false,
	is_loading: bool = false,
	text_align: f32 = 0.5,
	loc := #caller_location,
) -> (
	result: Button_Result,
) {
	object := get_object(hash(loc))

	if object.variant == nil {
		object.variant = Button{}
	}

	extras := &object.variant.(Button)

	style := get_current_style()
	kn.set_font(style.bold_font)
	label_text := kn.make_text(label, font_size, justify = text_align)

	object.size = linalg.ceil((label_text.size + global_state.style.text_padding * 2) / style.scale) * style.scale

	if begin_object(object) {

		object.animation.hover = animate(object.animation.hover, 0.1, .Hovered in object.state.current)
		object.animation.press = animate(object.animation.press, 0.08, .Pressed in object.state.current)
		extras.hold_time = max(
			extras.hold_time +
			delta_time() *
				f32(
					i32(.Pressed in object.state.current) -
					i32(.Pressed not_in object.state.current),
				),
			0,
		)
		if object.animation.press <= 0 {
			extras.hold_time = 0
		}
		draw_frames(int(extras.hold_time > 0))

		if .Hovered in object.state.current {
			set_cursor(.Pointing_Hand)
		}

		if point_in_box(global_state.mouse_pos, object.box) {
			hover_object(object)
		}

		extras.active_time = animate(extras.active_time, 0.15, active)

		if object_is_visible(object) {
			text_color: kn.Color = get_current_style().color.content
			rounding := get_current_options().radius

			switch accent {
			case .Primary:
				base_color := kn.mix(0.15 * (object.animation.hover + object.animation.press), style.color.accent, kn.White)
				stroke_color := base_color
				fill_color := kn.mix(
					f32(i32(delay > 0)) * object.animation.press,
					base_color,
					style.color.button_background,
				)
				kn.add_box(object.box, rounding, fill_color)
				if delay > 0 && object.animation.press > 0 {
					kn.push_scissor(kn.make_box(object.box, rounding))
					kn.add_box(
						get_box_cut_bottom(
							object.box,
							box_height(object.box) *
							ease.cubic_in(clamp(extras.hold_time / delay, 0, 1)),
						),
						paint = base_color,
					)
					kn.pop_scissor()
					kn.add_box_lines(
						object.box,
						style.line_width,
						rounding,
						kn.fade(stroke_color, object.animation.press),
					)
					kn.add_box(
						object.box,
						rounding,
						kn.fade(stroke_color, 1 - object.animation.press),
					)
				}
			case .Normal:
				color := kn.mix(extras.active_time, style.color.button, style.color.accent)
				kn.add_box_lines(object.box, style.line_width, rounding, paint = color)
				kn.add_box(
					object.box,
					rounding,
				paint = kn.fade(color, math.lerp(f32(0.5), f32(0.8), (object.animation.hover + object.animation.press) * 0.5)),
				)
			case .Subtle:
				kn.add_box(
					object.box,
					rounding,
					paint = kn.fade(
						style.color.button,
						max((object.animation.hover + object.animation.press) * 0.5, f32(i32(active))) *
						0.75,
					),
				)
			}

			if is_loading {
				kn.add_spinner(
					box_center(object.box),
					box_height(object.box) * 0.3,
					style.color.accent_content,
				)
			} else {
				kn.add_text(
					label_text,
					{
						math.lerp(
							object.box.lo.x + style.text_padding.x,
							object.box.hi.x - style.text_padding.x,
							text_align,
						),
						box_center_y(object.box),
					} - label_text.size * {0, 0.5},
					paint = text_color,
				)
			}
		}

		result.clicked = object_was_clicked(object, with = .Left) && extras.hold_time >= delay
		result.pressed = .Pressed in object.state.current
		result.hovered = .Hovered in object.state.current
		result.click_count = object.click.count

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
			kn.add_box(self.box, paint = kn.Paint{kind = .Skeleton})
		}
		kn.add_box(
			self.box,
			core.style.rounding,
			paint = kn.fade(core.get_current_style().color.substance, self.hover_time * 0.5),
		)
		// draw_rounded_box_stroke(self.box, core.style.rounding, 1, core.get_current_style().color.substance)
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
	text_layout = kn.make_text(
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
		kn.add_box(
			self.box,
			rounding,
			kn.fade(
				kn.mix(self.hover_time, core.get_current_style().color.field, core.get_current_style().color.accent),
				math.lerp(f32(0.75), f32(1.0), self.hover_time),
			),
		)
		kn.add_text(text_layout, box_center(self.box), core.get_current_style().color.content)
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
