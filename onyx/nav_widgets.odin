package onyx

import "core:math"
import "core:math/ease"
import "core:math/linalg"

Breadcrumb_Info :: struct {
	using _: Generic_Widget_Info,
	index: int,
	options: []string,
	is_tail: bool,
}

Breadcrumb_Result :: struct {
	using _: Generic_Widget_Result,
	index: Maybe(int),
}

make_breadcrumb :: proc(info: Breadcrumb_Info, loc := #caller_location) -> Breadcrumb_Info {
	info := info
	info.id = hash(loc)
	text_options := Text_Options{
		font = core.style.fonts[.Regular],
		size = core.style.button_text_size,
	}
	text_size := measure_text({
		text = info.options[info.index],
		options = text_options,
	})
	info.desired_size = text_size
	if !info.is_tail {
		info.desired_size.x += 16
	}
	if len(info.options) > 0 {
		info.desired_size.x += 20
	}
	info.fixed_size = true
	return info
}

display_breadcrumb :: proc(info: Breadcrumb_Info) -> (result: Breadcrumb_Result) {
	widget := get_widget(info)
	widget.box = next_widget_box(info)
	context.allocator = widget.allocator
	result.self = widget

	widget.hover_time = animate(widget.hover_time, 0.1, .Hovered in widget.state)

	if widget.visible {
		draw_text(widget.box.lo, {
			text = info.options[info.index],
			options = Text_Options{
				font = core.style.fonts[.Regular],
				size = core.style.button_text_size,
			},
		}, fade(core.style.color.content, 0.5 + 0.5 * widget.hover_time))
		if len(info.options) > 0 {
			origin: [2]f32 = {math.floor(widget.box.hi.x - 24), box_center_y(widget.box)}
			begin_path()
				point(origin + {-4, -2})
				point(origin + {0, 2})
				point(origin + {4, -2})
				stroke_path(2, fade(core.style.color.content, 0.5))
			end_path()
		}
		if !info.is_tail {
			origin: [2]f32 = {math.floor(widget.box.hi.x - 10), box_center_y(widget.box)}
			begin_path()
				point(origin + {-2, 6})
				point(origin + {2, -6})
				stroke_path(2, fade(core.style.color.content, 0.5))
			end_path()
		}
	}

	widget.focus_time = animate(widget.focus_time, 0.2, .Focused in widget.state)
	
	if .Focused in widget.state {
		layer_height: f32 = f32(len(info.options) - 1) * 30 + 10
		box: Box = {
			{
				widget.box.lo.x,
				widget.box.hi.y + 10,
			},
			{
				widget.box.hi.x,
				widget.box.hi.y + 10 + layer_height,
			},
		}

		begin_layer({
			box = box,
			origin = {box_center_x(box), box.lo.y},
			scale = ([2]f32)(ease.cubic_in_out(widget.focus_time)),
		})
			foreground()
			shrink(5)
			side(.Top); set_height(30)
			set_width_fill()
			for option, o in info.options {
				if o == info.index do continue
				push_id(o)
					if was_clicked(do_button({
						text = option,
						kind = .Ghost,
					})) {
						result.index = o
					}
				pop_id()
			}
		end_layer()
	}

	if .Hovered in widget.state {
		core.cursor_type = .POINTING_HAND
	}

	commit_widget(widget, point_in_box(core.mouse_pos, widget.box))

	return
}

do_breadcrumb :: proc(info: Breadcrumb_Info, loc := #caller_location) -> Breadcrumb_Result {
	return display_breadcrumb(make_breadcrumb(info, loc))
}
