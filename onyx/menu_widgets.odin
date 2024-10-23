package onyx

import "core:fmt"
import "core:math"
import "core:math/ease"
import "core:math/linalg"

@(deferred_out=__menu_bar)
menu_bar :: proc() -> bool {
	begin_layout({}) or_return
	box := layout_box()
	draw_rounded_box_fill(box, core.style.rounding, core.style.color.background)
	draw_rounded_box_stroke(box, core.style.rounding, 1, core.style.color.substance)
	shrink_layout(core.style.menu_padding)
	return true
}
@(private)
__menu_bar :: proc(ok: bool) {
	if ok {
		end_layout()
	}
}

Menu_Info :: struct {
	using _:    Widget_Info,
	text:       string,
	menu_align: Alignment,
	text_job:   Text_Job,
}

init_menu :: proc(using info: ^Menu_Info, loc := #caller_location) -> bool {
	id = hash(loc)
	self = get_widget(id) or_return
	text_info := Text_Info {
		text    = text,
		size    = core.style.button_text_size,
		font    = core.style.default_font,
		align_v = .Middle,
		align_h = .Middle,
	}
	text_job, _ = make_text_job(text_info)
	desired_size = text_job.size + core.style.text_padding
	return true
}

begin_menu :: proc(info: ^Menu_Info) -> bool {
	begin_widget(info) or_return

	if info.self.visible {
		draw_rounded_box_fill(
			info.self.box,
			core.style.rounding,
			alpha_blend_colors(core.style.color.background, core.style.color.substance, info.self.hover_time * 0.5),
		)
		draw_rounded_box_stroke(info.self.box, core.style.rounding, 1, core.style.color.substance)
		text_pos := box_center(info.self.box) + [2]f32{-10, 0}
		draw_text_glyphs(info.text_job, text_pos, core.style.color.content)
		draw_arrow(
			{text_pos.x + info.text_job.size.x / 2 + 10, text_pos.y},
			5,
			core.style.color.content,
		)
	}

	menu_behavior(info.self)

	if .Open in info.self.state {
		menu_layer := get_popup_layer_info(info.self, info.self.menu.size)
		if .Open not_in info.self.last_state {
			menu_layer.options += {.Invisible}
		}
		if !begin_layer(&menu_layer) {
			info.self.state -= {.Open}
		}
	}
	if .Open in info.self.state {
		push_id(info.self.id)
		draw_shadow(layout_box(), info.self.open_time)
		background()
		shrink_layout(core.style.menu_padding)
		set_width_fill()
		set_height_auto()
	}

	return .Open in info.self.state
}

end_menu :: proc() -> bool {
	self := current_widget().? or_return
	if .Open in self.state {
		pop_id()

		layout := current_layout().?
		self.menu.size = layout.content_size + layout.spacing_size
		layer := current_layer().?
		if (.Hovered not_in layer.state && .Focused not_in self.state) || .Clicked in layer.state {
			self.state -= {.Open}
		}

		draw_rounded_box_stroke(layer.box, core.style.rounding, 1, core.style.color.substance)

		end_layer()
	}
	end_widget()
	return true
}

@(deferred_none = __menu)
menu :: proc(info: Menu_Info, loc := #caller_location) -> bool {
	info := info
	init_menu(&info, loc) or_return
	return begin_menu(&info)
}

@(private)
__menu :: proc() {
	end_menu()
}

Menu_Item_Info :: struct {
	using _:  Widget_Info,
	text:     string,
	text_job: Text_Job,
	clicked:  bool,
}

init_menu_item :: proc(info: ^Menu_Item_Info) -> bool {
	info.self = get_widget(info.id) or_return
	info.text_job = make_text_job(
		{
			text = info.text,
			font = core.style.default_font,
			size = core.style.button_text_size,
			align_h = .Middle,
			align_v = .Middle,
		},
	) or_return
	info.desired_size = info.text_job.size + core.style.text_padding * 2
	return true
}

menu_item :: proc(info: Menu_Item_Info, loc := #caller_location) -> Menu_Item_Info {
	info := info
	if info.id == 0 do info.id = hash(loc)

	if init_menu_item(&info) {
		if begin_widget(&info) {
			defer end_widget()

			button_behavior(info.self)

			if info.self.visible {
				if info.self.hover_time > 0.0 {
					draw_rounded_box_fill(
						info.self.box,
						core.style.rounding,
						fade(core.style.color.substance, info.self.hover_time * 0.5),
					)
				}
				draw_text_glyphs(
					info.text_job,
					box_center(info.self.box),
					core.style.color.content,
				)
			}

			info.clicked = .Clicked in info.self.state
		}
	}

	return info
}
