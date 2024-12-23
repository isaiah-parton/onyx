package onyx

import "../vgo"
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
	active: bool,
	press_time:   f32,
	hover_time: f32,
	rounding: 		[4]f32,
	font_index:   Maybe(int),
	font_size:    Maybe(f32),
	color:        Maybe(vgo.Color),
	waves: 				Wave_Effects,
	text_layout:  vgo.Text_Layout,
}

Button_Result :: struct {
	clicked: bool,
	hovered: bool,
}

button :: proc(
	text: string,
	style: Button_Style = .Primary,
	rounding: [4]f32 = global_state.style.rounding,
	font_size: f32 = global_state.style.default_text_size,
	active: bool = false,
	loc := #caller_location,
) -> (
	result: Button_Result,
) {
	object := persistent_object(hash(loc))
	if object.variant == nil {
		object.variant = Button {
			object = object,
		}
	}
	self := &object.variant.(Button)
	self.text_layout = vgo.make_text_layout(text, font_size, global_state.style.default_font)
	self.rounding = rounding
	self.active = active
	self.placement = next_user_placement()
	set_object_desired_size(object, self.text_layout.size + global_state.style.text_padding * 2)
	if begin_object(object) {
		result.clicked = object_was_clicked(self, with = .Left)
		result.hovered = .Hovered in self.state.previous
		end_object()
	}
	return
}

display_button :: proc(self: ^Button) {
	handle_object_click(self)
	button_behavior(self)
	if object_is_visible(self) {
		bg_color := self.color.? or_else global_state.style.color.substance
		bg_color = vgo.blend(bg_color, global_state.style.color.accent, self.press_time)

		vgo.fill_box(
			self.box,
			self.rounding,
			vgo.mix(0.2 * self.hover_time, bg_color, vgo.WHITE),
		)

		vgo.push_scissor(vgo.make_box(self.box, self.rounding))
 		draw_and_update_wave_effects(self, &self.waves)
		vgo.pop_scissor()

		if !self.is_loading {
			vgo.fill_text_layout(
				self.text_layout,
				box_center(self.box),
				align = 0.5,
				paint = global_state.style.color.accent_content,
			)
		}

		if self.is_loading {
			vgo.spinner(box_center(self.box), box_height(self.box) * 0.3, global_state.style.color.accent_content)
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
