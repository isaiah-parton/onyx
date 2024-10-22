package onyx

import "base:intrinsics"
import "core:fmt"
import "core:math"
import "core:math/ease"
import "core:math/linalg"

Selector_Info :: struct {
	using _:    Widget_Info,
	text:       string,
	menu_align: Alignment,
	text_job:   Text_Job,
}

Menu_State :: struct {
	size:      [2]f32,
	open_time: f32,
}

init_selector :: proc(using info: ^Selector_Info, loc := #caller_location) -> bool {
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
	desired_size = text_job.size + {40, 10}
	return true
}

begin_selector :: proc(using info: ^Selector_Info) -> bool {
	begin_widget(info) or_return

	kind := widget_kind(self, Menu_State)
	if self.visible {
		draw_rounded_box_fill(
			self.box,
			core.style.rounding,
			fade(core.style.color.substance, self.hover_time * 0.5),
		)
		draw_rounded_box_stroke(self.box, core.style.rounding, 1, core.style.color.substance)
		text_pos := box_center(self.box) + [2]f32{-10, 0}
		draw_text_glyphs(text_job, text_pos, core.style.color.content)
		draw_arrow(
			{text_pos.x + info.text_job.size.x / 2 + 10, text_pos.y},
			5,
			core.style.color.content,
		)
	}

	menu_behavior(self)

	if .Open in self.state {
		menu_layer := get_popup_layer_info(self, kind.size)
		if !begin_layer(&menu_layer) {
			self.state -= {.Open}
		}
	}
	if .Open in self.state {
		push_id(self.id)
		draw_shadow(layout_box(), self.open_time)
		foreground()
		set_width_auto()
		set_height_auto()
	}

	return .Open in self.state
}

end_selector :: proc() -> bool {
	self := current_widget().? or_return
	if .Open in self.state {
		pop_id()

		layout := current_layout().?
		kind := widget_kind(self, Menu_State)
		kind.size = layout.content_size + layout.spacing_size
		layer := current_layer().?
		if (.Hovered not_in layer.state && .Focused not_in self.state) || .Clicked in layer.state {
			self.state -= {.Open}
		}
		draw_rounded_box_fill(
			current_layer().?.box,
			core.style.rounding,
			fade(core.style.color.foreground, 1 - self.open_time),
		)
		end_layer()
	}
	end_widget()
	return true
}

@(deferred_none = __selector)
selector :: proc(info: Selector_Info, loc := #caller_location) -> bool {
	info := info
	init_selector(&info, loc) or_return
	return begin_selector(&info)
}

@(private)
__selector :: proc() {
	end_selector()
}

Selector_Option_Kind :: enum {
	Dot,
	Check,
}

Selector_Option_Info :: struct {
	using _:  Widget_Info,
	text:     string,
	state:    bool,
	kind:     Selector_Option_Kind,
	text_job: Text_Job,
	clicked:  bool,
}

init_selector_option :: proc(using info: ^Selector_Option_Info, loc := #caller_location) -> bool {
	id = hash(loc)
	self = get_widget(id) or_return
	text_job, _ = make_text_job(
		{
			text = text,
			size = core.style.button_text_size,
			font = core.style.default_font,
			align_v = .Middle,
		},
	)
	desired_size = text_job.size + {20, 10}
	desired_size.x += desired_size.y
	return true
}

add_selector_option :: proc(using info: ^Selector_Option_Info) -> bool {
	begin_widget(info) or_return
	defer end_widget()

	button_behavior(self)

	if self.visible {
		draw_rounded_box_fill(
			self.box,
			core.style.rounding,
			fade(core.style.color.substance, self.hover_time * 0.5),
		)
		if info.state {
			switch info.kind {
			case .Check:
				draw_check(self.box.lo + box_height(self.box) / 2, 5, core.style.color.content)
			case .Dot:
				draw_circle_fill(
					self.box.lo + box_height(self.box) / 2,
					5,
					core.style.color.content,
				)
			}
		}
		draw_text_glyphs(
			info.text_job,
			{self.box.lo.x + box_height(self.box), box_center_y(self.box)},
			core.style.color.content,
		)
	}

	clicked = .Clicked in self.state
	return true
}

selector_option :: proc(
	info: Selector_Option_Info,
	loc := #caller_location,
) -> Selector_Option_Info {
	info := info
	if init_selector_option(&info, loc) {
		add_selector_option(&info)
	}
	return info
}

enum_selector :: proc(value: ^$T, loc := #caller_location) where intrinsics.type_is_enum(T) {
	if value == nil do return
	info := Selector_Info {
		text = fmt.tprint(value^),
	}
	if !init_selector(&info, loc) do return
	if begin_selector(&info) {
		shrink(3)
		set_side(.Top)
		set_width_fill()
		for member, m in T {
			push_id(m)
			if selector_option({text = fmt.tprint(member), state = value^ == member}).clicked {
				value^ = member
			}
			pop_id()
		}
	}
	end_selector()
}
