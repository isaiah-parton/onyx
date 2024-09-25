package onyx

import "core:math"
import "core:math/ease"
import "core:math/linalg"

Selector_Info :: struct {
	using _:    Generic_Widget_Info,
	text:       string,
	menu_align: Alignment,
	__text_job: Text_Job,
}

Menu_Widget_Kind :: struct {
	size:      [2]f32,
	open_time: f32,
}

make_selector :: proc(info: Selector_Info, loc := #caller_location) -> Selector_Info {
	info := info
	info.id = hash(loc)
	text_info := Text_Info {
		text    = info.text,
		size    = core.style.button_text_size,
		font    = core.style.fonts[.Medium],
		align_v = .Middle,
		align_h = .Middle,
	}
	info.__text_job, _ = make_text_job(text_info)
	info.desired_size = info.__text_job.size + {40, 10}
	return info
}

begin_selector :: proc(info: Selector_Info, loc := #caller_location) -> bool {
	widget := begin_widget(info) or_return
	kind := widget_kind(widget, Menu_Widget_Kind)
	if widget.visible {
		draw_rounded_box_fill(
			widget.box,
			core.style.rounding,
			fade(core.style.color.substance, widget.hover_time),
		)
		if widget.hover_time < 1 {
			draw_rounded_box_stroke(widget.box, core.style.rounding, 1, core.style.color.substance)
		}
		text_pos := box_center(widget.box) + [2]f32{-10, 0}
		draw_text_glyphs(info.__text_job, text_pos, core.style.color.content)
		draw_arrow(
			{text_pos.x + info.__text_job.size.x / 2 + 10, text_pos.y},
			5,
			core.style.color.content,
		)
	}

	menu_behavior(widget)

	if .Open in widget.state {
		menu_box := get_menu_box(widget.box, kind.size)
		layer_origin := menu_box.lo

		#partial switch info.menu_align {
		case .Far:
			layer_origin.x += box_width(menu_box)
		case .Middle:
			layer_origin.x += box_width(menu_box) / 2
		}

		open_time := ease.quadratic_out(kind.open_time)
		scale: f32 = 0.7 + 0.3 * open_time

		begin_layer(
			{
				id = widget.id,
				box = menu_box,
				origin = layer_origin,
				scale = [2]f32{scale, scale},
				opacity = open_time,
			},
		)
		foreground()
		set_width_auto()
		set_height_auto()
	}


	return .Open in widget.state
}

end_selector :: proc() {
	widget := current_widget().?
	if .Open in widget.state {
		layout := current_layout().?
		kind := widget_kind(widget, Menu_Widget_Kind)
		kind.size = layout.content_size + layout.spacing_size
		layer := current_layer().?
		if .Hovered not_in layer.state && .Focused not_in widget.state {
			widget.state -= {.Open}
		}
		end_layer()
	}
	end_widget()
}

@(deferred_out = __do_selector)
do_selector :: proc(info: Selector_Info, loc := #caller_location) -> bool {
	return begin_selector(make_selector(info, loc))
}

@(private)
__do_selector :: proc(ok: bool) {
	end_selector()
}

Selector_Option_Kind :: enum {
	Dot,
	Check,
}

Selector_Option_Info :: struct {
	using _:    Generic_Widget_Info,
	text:       string,
	state:      bool,
	kind:       Selector_Option_Kind,
	__text_job: Text_Job,
}

make_selector_option :: proc(
	info: Selector_Option_Info,
	loc := #caller_location,
) -> Selector_Option_Info {
	info := info
	info.id = hash(loc)
	text_info := Text_Info {
		text    = info.text,
		size    = core.style.button_text_size,
		font    = core.style.fonts[.Medium],
		align_v = .Middle,
	}
	info.__text_job, _ = make_text_job(text_info)
	info.desired_size = info.__text_job.size + {20, 10}
	info.desired_size.x += info.desired_size.y
	return info
}

add_selector_option :: proc(info: Selector_Option_Info) -> (result: Generic_Widget_Result) {
	widget, ok := begin_widget(info)
	if !ok do return

	result.self = widget

	button_behavior(widget)

	if widget.visible {
		draw_rounded_box_fill(
			widget.box,
			core.style.rounding,
			fade(core.style.color.substance, widget.hover_time),
		)
		if info.state {
			switch info.kind {
			case .Check:
				draw_check(widget.box.lo + box_height(widget.box) / 2, 5, core.style.color.content)
			case .Dot:
				draw_arc_fill(
					widget.box.lo + box_height(widget.box) / 2,
					5,
					0,
					math.TAU,
					core.style.color.content,
				)
			}
		}
		draw_text_glyphs(
			info.__text_job,
			{widget.box.lo.x + box_height(widget.box), box_center_y(widget.box)},
			core.style.color.content,
		)
	}
	end_widget()
	return
}

do_selector_option :: proc(
	info: Selector_Option_Info,
	loc := #caller_location,
) -> Generic_Widget_Result {
	return add_selector_option(make_selector_option(info, loc))
}
